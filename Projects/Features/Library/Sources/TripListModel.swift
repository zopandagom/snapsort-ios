import Core
import Foundation
import Observation
import PhotoLibraryInterface
import PhotoStoreInterface

/// 여행 폴더 목록 화면의 상태와 로직 (docs/ARCHITECTURE.md §4 여행 폴더).
/// 보관함의 여행 카드를 누르면 연다. 목록 화면은 한 번에 하나만 열리므로 App 이 하나를 소유한다.
/// 목록은 지오코딩하지 않는다(MapClient 를 받지 않는다). 장소 이름과 여행지 시간대는 상세를 열 때 캐시된 것만 쓴다.
/// 썸네일 칸은 카테고리 화면과 같은 보관 규칙을 쓰도록 `CategoryModel.thumbnailScreenAppeared(category: .travel)` 로 빌린다.
/// 저장소 변경·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
@MainActor
@Observable
public final class TripListModel {
  /// 목록 내용. 화면을 다시 열거나 상세에서 돌아오면 지난 목록을 둔 채 다시 읽는다.
  public private(set) var content: TripListContent = .loading
  /// 사용자가 고른 사진만 읽을 수 있는 제한 접근인지. 고른 사진만으로 여행을 찾았다고 안내한다. 읽을 때마다 다시 읽는다.
  public private(set) var isLimited: Bool
  /// 기간 날짜 표시가 쓰는 기기 달력. 읽을 때와 `dayChanged()` 때 기기 달력의 사본을 담는다(`GifticonListModel.calendar` 와 같은 이유).
  public private(set) var calendar: Calendar

  /// `onAppear()` 를 시작할 때마다 하나씩 올린다. 내용은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안(`onAppear()` 가 구독하는 동안)만 있다.
  /// 상세가 열려 있는 동안은 목록 화면의 `.task` 도 끝나 없다. 그동안 온 신호는 버리고, 돌아오면 한 번 다시 읽는다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let currentLocale: @Sendable () -> Locale

  /// - Parameters:
  ///   - photoLibrary: 제한 접근인지 읽는 데만 쓴다.
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다(그때는 여행 카드가 없어 이 화면에 오지 않는다).
  ///   - calendar: 기기 달력. 읽을 때와 `dayChanged()` 때 부른다. 시간대를 모르는 여행의 기간을 이 시간대로 계산한다(`TripPeriod`).
  ///   - locale: 캐시된 장소 이름을 고르는 기기 로캘. 읽을 때마다 한 번 부른다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    photoStore: (any PhotoStoreClient)?,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    locale: @escaping @Sendable () -> Locale = { .current }
  ) {
    self.photoLibrary = photoLibrary
    self.photoStore = photoStore
    self.currentCalendar = calendar
    self.currentLocale = locale
    self.calendar = calendar()
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  /// 목록을 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  public func onAppear() async {
    self.generation += 1
    let generation = self.generation
    if self.content == .failed {
      self.content = .loading
    }
    guard let photoStore = self.photoStore else {
      self.content = .failed
      return
    }
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.reloadRequests = continuation
    // 처음 읽기.
    continuation.yield()
    for await _ in requests {
      guard self.isCurrent(generation) else { return }
      await self.reload(photoStore: photoStore, generation: generation)
    }
    // 화면이 닫혔다. 이후 신호와 다시 시도는 버리고, 다음 진입이 처음 읽기를 한다.
    if self.isCurrent(generation) {
      self.reloadRequests = nil
    }
  }

  /// 저장소 내용(여행 판정·장소 이름 캐시)이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 날짜나 시간대가 바뀌었다(자정을 넘김, 시간대 변경, 앱 복귀). 달력을 다시 담고, 화면이 열려 있으면 다시 읽는다
  /// (시간대를 모르는 여행의 기간은 기기 시간대로 계산하므로 다시 계산한다).
  public func dayChanged() {
    self.refreshCalendar()
    self.reloadRequests?.yield()
  }

  // MARK: - Private

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 저장소 호출 하나라도 실패하면 처음 읽기는 실패이고, 다시 읽기면 지난 목록을 둔다.
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    self.refreshCalendar()
    let isLimited = self.photoLibrary.accessState() == .limited
    if self.isLimited != isLimited {
      self.isLimited = isLimited
    }
    let calendar = self.calendar
    let items: [TripFolderItem]
    do throws(PhotoStoreError) {
      items = try await Self.items(photoStore: photoStore, calendar: calendar, locale: self.currentLocale())
    } catch {
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      if case .loaded = self.content {
        return
      }
      self.content = .failed
      return
    }
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    // 진행률 대부분은 여행을 바꾸지 않으므로, 같으면 대입하지 않아 다시 그리지 않는다.
    guard self.content != .loaded(items) else { return }
    self.content = .loaded(items)
  }

  /// 여행 → 캐시된 이름·시간대(한 번) → 대표 사진(한 번) 순서로 읽어 최신 여행이 위인 줄을 만든다.
  private static func items(
    photoStore: any PhotoStoreClient,
    calendar: Calendar,
    locale: Locale
  ) async throws(PhotoStoreError) -> [TripFolderItem] {
    // 사진 식별자가 없는 여행은 열 수 없고 줄 식별자도 없어 뺀다.
    let trips = try await photoStore.trips().filter { !$0.assetIDs.isEmpty }
    guard !trips.isEmpty else { return [] }
    let keys = Set(trips.compactMap(\.placeKey))
    let places = keys.isEmpty
      ? [:]
      : try await photoStore.places(for: keys, localeIdentifier: locale.identifier)
    var candidateIDs: [ImageAsset.ID] = []
    for trip in trips {
      candidateIDs.append(contentsOf: trip.coverCandidateIDs)
    }
    let assets = try await photoStore.assets(ids: candidateIDs)
    let assetsByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return trips
      .map { trip in
        let cached = trip.placeKey.flatMap { places[$0] }
        let placeName: String? = if case let .named(name) = cached?.name {
          name
        } else {
          nil
        }
        return TripFolderItem(
          trip: trip,
          period: TripPeriod(
            trip: trip,
            calendar: calendar,
            knownTimeZone: cached?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
          ),
          // 대표 사진 후보 규칙(가운데 → 첫 → 마지막)은 보관함 여행 카드와 같은 `Trip.coverCandidateIDs` 다. 지워진 사진은 저장소에 없어 다음 후보를 쓴다.
          cover: trip.coverCandidateIDs.lazy.compactMap { assetsByID[$0] }.first,
          placeName: placeName
        )
      }
      .sorted { lhs, rhs in
        if lhs.trip.startDate != rhs.trip.startDate {
          return lhs.trip.startDate > rhs.trip.startDate
        }
        return lhs.trip.endDate > rhs.trip.endDate
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

/// 여행 폴더 목록 내용.
public enum TripListContent: Equatable {
  case loading
  /// 빈 배열이면 여행이 없다. 시작 시각 내림차순(같으면 끝 시각 내림차순)이다.
  case loaded([TripFolderItem])
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 목록이 있을 때 실패하면 지난 목록을 둔다.
  case failed
}

/// 여행 폴더 목록의 한 줄.
public struct TripFolderItem: Sendable, Hashable, Identifiable {
  /// 첫 사진 식별자. 여행 판정이 다시 돌아도 같은 여행이면 대개 같다.
  public var id: ImageAsset.ID {
    self.trip.assetIDs.first ?? ""
  }

  public let trip: Trip
  /// 캐시된 여행지 시간대가 있으면 그것으로, 없으면 대체 규칙으로 계산한 기간.
  public let period: TripPeriod
  public var photoCount: Int {
    self.trip.assetIDs.count
  }

  /// 가운데·첫·마지막 사진 중 저장소에 있는 첫 사진. 없으면 nil(대체 타일).
  public let cover: ImageAsset?
  /// 지금 로캘로 캐시된 장소 이름. 캐시가 없거나, 이름을 못 찾았거나(`.unnamed`), 다른 로캘로 캐시됐으면 nil(기간을 제목으로 쓴다).
  public let placeName: String?

  public init(trip: Trip, period: TripPeriod, cover: ImageAsset?, placeName: String?) {
    self.trip = trip
    self.period = period
    self.cover = cover
    self.placeName = placeName
  }
}
