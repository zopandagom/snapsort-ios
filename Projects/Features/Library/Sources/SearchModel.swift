import Core
import Foundation
import Observation
import PhotoStoreInterface

/// 보관함 검색의 상태와 로직 (docs/ARCHITECTURE.md §4 검색).
/// 검색 화면이 열릴 때 저장소를 한 번 읽어 메인 밖에서 색인을 만들고, 입력마다 0.25초 기다린 뒤 메인 밖에서 거른다.
/// 장소 이름은 캐시된 것만 쓰고 묻지 않는다(Map Client 를 받지 않는다). 검색어·결과(OCR 줄)는 화면에만 보이고 로그에 남기지 않는다
/// (docs/CONVENTIONS.md §4).
/// 저장소 변경·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
/// 썸네일 칸은 `CategoryModel.thumbnailScreenAppeared(scope: .search)` 로 빌린다.
@MainActor
@Observable
public final class SearchModel {
  /// 검색 필드 글자 그대로(조합 중 글자 포함). 고치지 않고 담는다.
  public private(set) var query = ""
  public private(set) var loadState: SearchLoadState = .loading
  /// 마지막으로 읽은 OCR 대기 수. 읽기 전·닫은 뒤 0.
  public private(set) var pendingTextCount = 0
  /// 지금(또는 바로 앞) 검색어의 결과. 검색어가 비었거나 이 검색어로 아직 결과가 없으면 nil.
  /// 새 검색어를 거르는 동안에는 앞 결과를 둔다(`results.query` 가 그 검색어).
  public private(set) var results: SearchResults?
  /// 여행 줄 기간·사진 줄 날짜 표시가 쓰는 기기 달력. 읽을 때와 `dayChanged()` 때 사본을 담는다(`TripListModel.calendar` 와 같은 이유).
  public private(set) var calendar: Calendar

  /// 낱말이 있는 검색어인지. View 가 안내와 결과를 고른다.
  public var hasQuery: Bool {
    !SearchQuery(self.query).isEmpty
  }

  /// `onAppear()` 를 시작할 때마다 하나씩 올린다. 읽기 결과는 지금 번호의 Task 만 반영한다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 검색 화면이 열려 있는 동안(`onAppear()` 가 구독하는 동안)만 있다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?
  /// 마지막으로 읽어 만든 색인과 줄 후보. 상세를 다녀와도 두고, 검색을 닫으면 놓는다.
  @ObservationIgnored private var source: SearchSource?
  /// 대조를 시작할 때마다(입력·지움·새 색인·닫힘) 하나씩 올린다. 늦게 끝난 대조 결과를 버린다.
  @ObservationIgnored private var matchGeneration = 0
  @ObservationIgnored private var matchTask: Task<Void, Never>?

  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let currentLocale: @Sendable () -> Locale
  @ObservationIgnored private let wait: Waiting
  @ObservationIgnored private let building: Building
  @ObservationIgnored private let matching: Matching

  /// 입력이 멈춘 뒤 이만큼 기다렸다가 거른다.
  static let debounceInterval: Duration = .milliseconds(250)

  /// 입력 뒤 대기. 테스트가 대기를 붙잡거나 건너뛰게 주입한다.
  typealias Waiting = @Sendable (Duration) async throws -> Void
  /// 읽은 목록으로 색인을 만드는 단계. 테스트가 이 단계에서 멈출 수 있게 주입한다.
  typealias Building = @Sendable (SearchLoad, SearchIndex?) async -> SearchSource
  /// 검색어를 색인에 대조하고 지금 결과와 비교하는 단계. 테스트가 이 단계에서 멈출 수 있게 주입한다.
  typealias Matching = @Sendable (SearchSource, String, SearchResults?) async -> (
    results: SearchResults,
    isUnchanged: Bool
  )

  /// - Parameters:
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다.
  ///   - calendar: 기기 달력. 읽을 때와 `dayChanged()` 때 부른다. 시간대를 모르는 여행의 기간을 이 시간대로 계산한다(`TripPeriod`).
  ///   - locale: 캐시된 장소 이름을 고르는 기기 로캘. 읽을 때마다 한 번 부른다.
  public convenience init(
    photoStore: (any PhotoStoreClient)?,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    locale: @escaping @Sendable () -> Locale = { .current }
  ) {
    self.init(
      photoStore: photoStore,
      calendar: calendar,
      locale: locale,
      wait: { try await Task.sleep(for: $0) },
      building: SearchComputing.source,
      matching: SearchComputing.results
    )
  }

  init(
    photoStore: (any PhotoStoreClient)?,
    calendar: @escaping @Sendable () -> Calendar,
    locale: @escaping @Sendable () -> Locale,
    wait: @escaping Waiting,
    building: @escaping Building,
    matching: @escaping Matching
  ) {
    self.photoStore = photoStore
    self.currentCalendar = calendar
    self.currentLocale = locale
    self.calendar = calendar()
    self.wait = wait
    self.building = building
    self.matching = matching
  }

  // MARK: - Events

  /// 저장소를 읽어 색인을 만들고, 검색 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  /// 상세에서 돌아오면 지난 색인과 결과를 둔 채 한 번 다시 읽는다.
  public func onAppear() async {
    self.generation += 1
    let generation = self.generation
    if self.loadState == .failed {
      self.loadState = .loading
    }
    guard let photoStore = self.photoStore else {
      self.loadState = .unavailable
      return
    }
    // 상세에 간 사이 대기 중이던 검색어가 걸러지지 않았으면 지난 색인으로 바로 거른다.
    // 돌아온 뒤 다시 읽기가 실패해도 검색 필드와 목록이 어긋난 채 남지 않게 한다.
    if self.source != nil, self.hasQuery, self.results?.query != self.query {
      self.startMatch(debounced: false)
    }
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.reloadRequests = continuation
    // 처음 읽기.
    continuation.yield()
    for await _ in requests {
      guard self.isCurrent(generation) else { return }
      await self.reload(photoStore: photoStore, generation: generation)
    }
    // 화면이 닫혔다. 이후 신호와 다시 시도는 버리고, 대기 중인 대조도 멈춘다. 다음 진입이 다시 읽는다.
    if self.isCurrent(generation) {
      self.reloadRequests = nil
      self.matchTask?.cancel()
      self.matchTask = nil
      self.matchGeneration += 1
    }
  }

  /// 검색 필드의 글자가 바뀌었다. 받은 글자는 고치지 않고 담고, 0.25초 뒤 거른다.
  public func queryChanged(_ text: String) {
    guard text != self.query else { return }
    self.query = text
    self.startMatch(debounced: true)
  }

  /// 저장소 내용이 바뀌었을 수 있다는 신호. 검색 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 검색 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.loadState == .failed, let reloadRequests = self.reloadRequests else { return }
    self.loadState = .loading
    reloadRequests.yield()
  }

  /// 검색 필드를 해제했고 검색어가 비었다. 색인(1만 장이면 수십 MB)과 결과를 놓는다. 늦게 끝나는 읽기·대조 결과는 버린다.
  public func searchDismissed() {
    self.generation += 1
    self.reloadRequests = nil
    self.matchTask?.cancel()
    self.matchTask = nil
    self.matchGeneration += 1
    self.source = nil
    self.results = nil
    self.pendingTextCount = 0
    if self.loadState != .unavailable {
      self.loadState = .loading
    }
  }

  /// 날짜나 시간대가 바뀌었다(자정을 넘김, 시간대 변경, 앱 복귀). 달력을 다시 담고, 열려 있으면 다시 읽는다
  /// (시간대를 모르는 여행의 기간은 기기 시간대로 계산하므로 다시 계산한다).
  public func dayChanged() {
    self.refreshCalendar()
    self.reloadRequests?.yield()
  }

  // MARK: - Private

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 저장소 호출 하나라도 실패하면 처음 읽기는 실패이고, 다시 읽기면 지난 색인과 결과를 둔다.
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    self.refreshCalendar()
    let calendar = self.calendar
    let locale = self.currentLocale()
    let load: SearchLoad
    do throws(PhotoStoreError) {
      let entries = try await photoStore.searchEntries()
      let categoryCounts = try await photoStore.categoryCounts()
      // 사진 식별자가 없는 여행은 열 수 없어 뺀다.
      let trips = try await photoStore.trips().filter { !$0.assetIDs.isEmpty }
      let keys = Set(trips.compactMap(\.placeKey))
      let places = keys.isEmpty
        ? [:]
        : try await photoStore.places(for: keys, localeIdentifier: locale.identifier)
      load = SearchLoad(
        entries: entries,
        categoryCounts: categoryCounts,
        trips: trips,
        places: places,
        calendar: calendar
      )
    } catch {
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      if self.source != nil {
        return
      }
      self.loadState = .failed
      return
    }
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    // 1만 장이면 정규화가 읽을 때마다 되풀이되므로 메인 밖에서 한다. 계산은 취소되지 않아, 돌아온 뒤 같은 규칙으로 버린다.
    let newSource = await self.building(load, self.source?.index)
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    self.source = newSource
    // 진행률 대부분은 같은 값이므로, 같으면 대입하지 않아 다시 그리지 않는다.
    if self.loadState != .loaded {
      self.loadState = .loaded
    }
    if self.pendingTextCount != load.entries.pendingTextCount {
      self.pendingTextCount = load.entries.pendingTextCount
    }
    // 지금 검색어를 새 색인으로 바로 다시 거른다(대기 없음).
    self.startMatch(debounced: false)
  }

  /// 앞 대기·대조를 취소하고 지금 검색어를 거른다. 낱말이 없으면 결과를 비우고 거르지 않는다.
  /// 그 사이 입력·지움·새 색인·닫힘이 오면 세대가 올라 늦게 끝난 결과를 버린다.
  /// `results` 는 이 함수와 아래 Task, `searchDismissed` 만 바꾸고 셋 모두 세대를 올린다.
  private func startMatch(debounced: Bool) {
    self.matchTask?.cancel()
    self.matchGeneration += 1
    let matchGeneration = self.matchGeneration
    let query = self.query
    guard !SearchQuery(query).isEmpty else {
      if self.results != nil {
        self.results = nil
      }
      self.matchTask = nil
      return
    }
    self.matchTask = Task {
      if debounced {
        do {
          try await self.wait(Self.debounceInterval)
        } catch {
          return
        }
      }
      // 색인이 아직 없으면 읽기가 끝날 때 다시 부른다.
      guard matchGeneration == self.matchGeneration, let source = self.source else { return }
      let (results, isUnchanged) = await self.matching(source, query, self.results)
      guard matchGeneration == self.matchGeneration else { return }
      if !isUnchanged {
        self.results = results
      }
    }
  }

  /// 같으면 대입하지 않아 다시 그리지 않는다.
  private func refreshCalendar() {
    let calendar = self.currentCalendar()
    if self.calendar != calendar {
      self.calendar = calendar
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }
}

/// 검색 목록 읽기 상태.
public enum SearchLoadState: Equatable {
  case loading
  case loaded
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 읽었으면 다시 읽기 실패는 지난 색인을 둔다.
  case failed
  /// App 이 저장소를 열지 못했다. 다시 시도가 없다.
  case unavailable
}

/// 한 검색어의 결과. 검색어가 같고 저장소 내용이 같으면 같은 값이다.
public struct SearchResults: Equatable, Sendable {
  /// 이 결과를 만든 검색어 원문.
  public let query: String
  /// 이름이 맞은 카테고리, `ImageCategory.allCases` 순서. 이미지가 없는 카테고리(여행은 열 수 있는 여행이 없음)는 빠진다.
  public let categories: [SearchCategoryHit]
  /// 캐시된 장소 이름이 맞은 여행, 시작 시각 내림차순(같으면 끝 시각 내림차순, 여행 폴더 목록과 같다).
  public let trips: [SearchTripHit]
  /// 최신순.
  public let images: [SearchHit]

  public var isEmpty: Bool {
    self.categories.isEmpty && self.trips.isEmpty && self.images.isEmpty
  }
}

public struct SearchCategoryHit: Equatable, Sendable, Identifiable {
  public let category: ImageCategory
  /// 여행은 여행 수, 나머지는 이미지 수.
  public let count: Int

  public var id: ImageCategory {
    self.category
  }
}

public struct SearchTripHit: Equatable, Sendable, Identifiable {
  public let trip: Trip
  /// 지금 로캘로 캐시된 장소 이름.
  public let placeName: String
  /// 캐시된 여행지 시간대가 있으면 그것으로, 없으면 대체 규칙으로 계산한 기간(여행 폴더 목록과 같다).
  public let period: TripPeriod

  /// 첫 사진 식별자. 여행 판정이 다시 돌아도 같은 여행이면 대개 같다.
  public var id: ImageAsset.ID {
    self.trip.assetIDs.first ?? ""
  }
}

// MARK: - 메인 밖 계산

/// 저장소에서 한 번에 읽은 값.
struct SearchLoad: Sendable {
  let entries: SearchEntries
  let categoryCounts: [ImageCategory: Int]
  /// 사진 식별자가 있는 여행.
  let trips: [Trip]
  let places: [RoundedCoordinate: CachedPlace]
  /// 읽기를 시작할 때 담은 기기 달력. 여행 기간 계산에 쓴다.
  let calendar: Calendar
}

/// 읽은 값으로 만든 색인과 줄 후보. 검색어마다 다시 만들지 않는다.
struct SearchSource: Sendable {
  let index: SearchIndex
  /// 카테고리마다 이미지 수. `.travel` 은 여행 수다.
  let categoryCounts: [ImageCategory: Int]
  /// 지금 로캘로 캐시된 이름(`.named`)이 있는 여행, 시작 시각 내림차순.
  let tripCandidates: [SearchTripHit]
}

/// 색인 만들기와 대조. 1만 장이면 정규화·대조가 입력과 진행률마다 되풀이되므로 메인 밖에서 한다(`CategorySectioning` 과 같은 방식).
enum SearchComputing {
  @concurrent
  static func source(from load: SearchLoad, reusing previous: SearchIndex?) async -> SearchSource {
    var categoryCounts = load.categoryCounts
    categoryCounts[.travel] = load.trips.isEmpty ? nil : load.trips.count
    let candidates = load.trips.compactMap { trip -> SearchTripHit? in
      guard let cached = trip.placeKey.flatMap({ load.places[$0] }), case let .named(name) = cached.name else {
        return nil
      }
      let period = TripPeriod(
        trip: trip,
        calendar: load.calendar,
        knownTimeZone: cached.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
      )
      return SearchTripHit(trip: trip, placeName: name, period: period)
    }
    .sorted { lhs, rhs in
      if lhs.trip.startDate != rhs.trip.startDate {
        return lhs.trip.startDate > rhs.trip.startDate
      }
      return lhs.trip.endDate > rhs.trip.endDate
    }
    return SearchSource(
      index: SearchIndex(entries: load.entries.entries, reusing: previous),
      categoryCounts: categoryCounts,
      tripCandidates: candidates
    )
  }

  /// `current` 와 같으면 `isUnchanged` 가 참이다.
  @concurrent
  static func results(
    in source: SearchSource,
    query text: String,
    comparingTo current: SearchResults?
  ) async -> (results: SearchResults, isUnchanged: Bool) {
    let query = SearchQuery(text)
    let categories = ImageCategory.allCases.compactMap { category -> SearchCategoryHit? in
      guard let count = source.categoryCounts[category], count > 0, query.matches(name: category.title) else {
        return nil
      }
      return SearchCategoryHit(category: category, count: count)
    }
    let trips = source.tripCandidates.filter { query.matches(name: $0.placeName) }
    let results = SearchResults(
      query: text,
      categories: categories,
      trips: trips,
      images: source.index.hits(for: query)
    )
    return (results, results == current)
  }
}
