import Core
import Foundation
import MapInterface
import Observation
import PhotoStoreInterface

/// 여행 폴더 상세 화면의 상태와 로직 (docs/ARCHITECTURE.md §4 여행 폴더).
/// 여행 사진 격자, 그 기간의 영수증·지도·문서 캡처 묶음, 장소 이름, 반올림 중심점 지도를 보인다. 상세 화면은 한 번에 하나만 열리므로
/// App 이 하나를 소유한다. 여행 판정은 저장소가 바뀔 때마다 다시 돌아 같은 여행도 값이 바뀌므로, 다시 읽을 때 사진이 가장 많이 겹치는
/// 여행(`Trip.bestMatch(in:)`)을 같은 여행으로 본다.
/// 장소 이름은 캐시에 없을 때만, 여행 중심점의 반올림 좌표(`Trip.placeKey`)로만 묻는다(`MapClient.placeName(near:locale:)`).
/// 받은 이름·시간대는 저장소에 캐시하고(미리 받기 `TripPlaceClient` 도 쓴다), 시간대를 받으면 다시 읽어 기간·캡처를 다시 계산한다.
/// 저장소 변경(장소 캐시 쓰기 포함)·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다.
@MainActor
@Observable
public final class TripDetailModel {
  /// 상세 내용. 사진 상세에서 돌아오거나 목록에서 같은 여행 값을 다시 열면 지난 내용을 둔 채 다시 읽는다.
  /// 그 밖에 목록에서 새로 열면(판정이 여행을 나눈 뒤 다른 쪽을 연 경우 포함) `.loading` 부터.
  public private(set) var content: TripDetailContent = .loading
  /// 장소 이름. 캐시에 있으면 바로, 없으면 묻는 동안 `.loading` 이다. 값은 늘 `placeNameRequest` 의 키·로캘 것이고,
  /// 내용이 `.loaded(detail)` 이면 그 키는 `detail.trip.placeKey` 다.
  public private(set) var placeName: TripPlaceNameState = .loading
  /// 기간 날짜 표시가 쓰는 기기 달력. 읽을 때와 `dayChanged()` 때 기기 달력의 사본을 담는다(`GifticonListModel.calendar` 와 같은 이유).
  public private(set) var calendar: Calendar
  /// 지금 내용·이름이 속한 상세 화면 인스턴스(View `@State visit`). View 는 자기 visit 과 같을 때만 내용을 그린다
  /// (다른 여행을 연 첫 프레임에 지난 여행이 비치지 않게. `CategoryView.content` 와 같은 이유).
  public private(set) var visit: UUID?

  /// `onAppear(trip:visit:)` 를 시작할 때마다 하나씩 올린다. 내용·이름은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안만 있다. 사진 상세가 열려 있는 동안은 이 화면의 `.task` 도 끝나 없다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?
  /// 이름을 물으라는 신호. 화면이 열려 있는 동안만 있다. 다시 읽기가 넣고 이름 루프가 차례로 꺼낸다. 마지막 신호만 남긴다.
  @ObservationIgnored private var placeRequests: AsyncStream<TripPlaceRequest>.Continuation?
  /// 다시 읽기의 기준 여행: 새 방문이면 누른 여행, 같은 방문 동안은 마지막으로 찾은 여행. 다시 읽을 때 이것과 사진이 가장 많이
  /// 겹치는 저장된 여행을 찾는다. 찾지 못해도(`.notFound`) 두어, 여행이 돌아오면 다시 찾는다.
  @ObservationIgnored private var currentTrip: Trip?
  /// `placeName` 의 주인(키·로캘). 키가 없는 여행이거나 아직 읽기 전이면 nil. 테스트가 읽는다.
  @ObservationIgnored private(set) var placeNameRequest: TripPlaceRequest?
  /// 이 방문에서 물은 키·로캘마다 마지막으로 안 상태. 묻는 중이면 `.loading`, 결과를 받았으면 그 결과(이름·이름 없음·못 찾음).
  /// 같은 방문에서 키가 돌아오면 캐시가 지워졌어도 이것을 다시 쓴다. 새 방문이면 비운다.
  @ObservationIgnored private var visitPlaces: [TripPlaceRequest: TripPlaceNameState] = [:]
  /// 이름 루프가 지금 기다리는 요청. 진입 번호와 함께 두어, 같은 진입에서 같은 요청을 기다리는 동안만 다음 신호를 건너뛴다.
  @ObservationIgnored private var waitingPlace: TripPlaceWait?
  @ObservationIgnored private var waitingPlaceCount = 0
  /// 키·로캘마다 진행 중인 이름 요청. 사진 상세에 갔다 오거나 판정이 키를 바꿨다 되돌려도 같은 요청을 이어받아 두 번 묻지 않는다.
  /// 끝나면 비운다.
  @ObservationIgnored private var inFlights: [TripPlaceRequest: TripPlaceInFlight] = [:]
  @ObservationIgnored private var inFlightCount = 0

  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let map: any MapClient
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let currentLocale: @Sendable () -> Locale
  @ObservationIgnored private let placeNameTimeout: Duration

  /// - Parameters:
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다(그때는 여행 카드가 없어 이 화면에 오지 않는다).
  ///   - map: 장소 이름을 묻는다. 이 화면에서 캐시에 이름이 없을 때 여행 중심점의 반올림 좌표로만 부른다.
  ///   - calendar: 기기 달력. 읽을 때와 `dayChanged()` 때 부른다. 시간대를 모르는 여행의 기간을 이 시간대로 계산한다(`TripPeriod`).
  ///   - locale: 장소 이름의 로캘. 읽을 때마다 한 번 부른다.
  public convenience init(
    photoStore: (any PhotoStoreClient)?,
    map: any MapClient,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    locale: @escaping @Sendable () -> Locale = { .current }
  ) {
    self.init(
      photoStore: photoStore,
      map: map,
      calendar: calendar,
      locale: locale,
      placeNameTimeout: Self.defaultPlaceNameTimeout
    )
  }

  /// - Parameter placeNameTimeout: 이름 응답을 기다리는 시간. 테스트가 짧게 준다.
  init(
    photoStore: (any PhotoStoreClient)?,
    map: any MapClient,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    locale: @escaping @Sendable () -> Locale = { .current },
    placeNameTimeout: Duration
  ) {
    self.photoStore = photoStore
    self.map = map
    self.currentCalendar = calendar
    self.currentLocale = locale
    self.placeNameTimeout = placeNameTimeout
    self.calendar = calendar()
  }

  // MARK: - Events

  /// 여행을 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호와 이름 요청을 처리한다.
  /// - Parameter visit: 이 상세 화면 인스턴스의 값(View `@State`). 같은 visit 으로 다시 나타나면(사진 상세에서 돌아옴) 이 방문에서
  ///   받은 이름 결과(이름·이름 없음·못 찾음)를 다시 쓰고 다시 묻지 않으며, 아직 `.loading` 이던 이름은 진행 중 요청을 이어받거나
  ///   (시한 안) 다시 묻는다.
  public func onAppear(trip: Trip, visit: UUID) async {
    self.generation += 1
    let generation = self.generation
    if self.visit != visit {
      // 목록에서 새로 열었다. 누른 여행을 기준으로 삼는다(지난 방문의 매칭을 쓰지 않는다).
      // 지난 내용은 같은 여행 값일 때만 둔다. 사진이 겹치는 것만으로는 두지 않는다(판정이 나뉜 뒤 다른 쪽일 수 있다).
      if self.currentTrip != trip {
        self.content = .loading
        self.setPlaceName(.loading, for: nil)
      }
      self.currentTrip = trip
      self.visit = visit
      self.visitPlaces = [:]
    } else if self.currentTrip == nil {
      // 일어나지 않지만(같은 visit 이면 앞선 진입이 넣었다) 기준이 없으면 누른 여행으로.
      self.currentTrip = trip
    }
    // 같은 visit(사진 상세에서 돌아옴)은 마지막 매칭을 그대로 기준으로 둔다. route 의 옛 값으로 되돌리지 않는다.
    if self.content == .failed {
      self.content = .loading
    }
    guard let photoStore = self.photoStore else {
      self.content = .failed
      self.setPlaceName(.unavailable, for: nil)
      return
    }
    let (reloads, reloadContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let (places, placeContinuation) = AsyncStream.makeStream(
      of: TripPlaceRequest.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    self.reloadRequests = reloadContinuation
    self.placeRequests = placeContinuation
    // 처음 읽기.
    reloadContinuation.yield()
    await withDiscardingTaskGroup { group in
      group.addTask { await self.runReloads(reloads, photoStore: photoStore, generation: generation) }
      group.addTask { await self.runPlaceRequests(places, photoStore: photoStore, generation: generation) }
    }
    // 화면이 닫혔다. 이후 신호와 다시 시도는 버리고, 다음 진입이 처음 읽기를 한다.
    if self.isCurrent(generation) {
      self.reloadRequests = nil
      self.placeRequests = nil
    }
  }

  /// 저장소 내용(여행 판정·캡처)이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 날짜나 시간대가 바뀌었다. 달력을 다시 담고, 화면이 열려 있으면 다시 읽는다
  /// (시간대를 모르는 여행의 기간과 캡처 범위는 기기 시간대로 계산하므로 다시 계산한다).
  public func dayChanged() {
    self.refreshCalendar()
    self.reloadRequests?.yield()
  }

  // MARK: - Reload

  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  private func runReloads(_ reloads: AsyncStream<Void>, photoStore: any PhotoStoreClient, generation: Int) async {
    for await _ in reloads {
      guard self.isCurrent(generation) else { return }
      await self.reload(photoStore: photoStore, generation: generation)
    }
  }

  /// 저장소 호출은 취소되지 않으므로, 돌아올 때마다 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 하나라도 실패하면 처음 읽기는 실패이고, 이미 내용(`.loaded`·`.notFound`)이 있으면 둔다.
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    self.refreshCalendar()
    guard let trip = self.currentTrip else { return }
    let localeIdentifier = self.currentLocale().identifier
    let result: ReloadResult
    do throws(PhotoStoreError) {
      result = try await self.read(
        trip,
        photoStore: photoStore,
        calendar: self.calendar,
        localeIdentifier: localeIdentifier,
        generation: generation
      )
    } catch {
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      if self.content == .loading || self.content == .failed {
        self.content = .failed
      }
      return
    }
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    switch result {
    case .stale:
      return
    case .notFound:
      // 판정이 바뀌어 여행이 사라졌다. 이름은 묻지 않는다. `currentTrip` 은 둬서 여행이 돌아오면 다시 찾는다.
      if self.content != .notFound {
        self.content = .notFound
      }
    case let .found(detail, cachedName):
      self.currentTrip = detail.trip
      // 진행률 대부분은 이 여행을 바꾸지 않으므로, 같으면 대입하지 않아 다시 그리지 않는다.
      if self.content != .loaded(detail) {
        self.content = .loaded(detail)
      }
      self.updatePlaceName(key: detail.trip.placeKey, cached: cachedName, localeIdentifier: localeIdentifier)
    }
  }

  /// 여행 → 캐시된 이름·시간대 → 사진 → 기간 캡처 순서로 읽는다. 도중에 화면이 닫히거나 다른 진입이 시작되면 `.stale` 이다.
  private func read(
    _ trip: Trip,
    photoStore: any PhotoStoreClient,
    calendar: Calendar,
    localeIdentifier: String,
    generation: Int
  ) async throws(PhotoStoreError) -> ReloadResult {
    let trips = try await photoStore.trips()
    guard self.isCurrent(generation), !Task.isCancelled else { return .stale }
    guard let match = trip.bestMatch(in: trips) else { return .notFound }
    let key = match.placeKey
    var cached: CachedPlace?
    if let key {
      cached = try await photoStore.places(for: [key], localeIdentifier: localeIdentifier)[key]
      guard self.isCurrent(generation), !Task.isCancelled else { return .stale }
    }
    let period = TripPeriod(
      trip: match,
      calendar: calendar,
      knownTimeZone: cached?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    )
    let photos = try await photoStore.assets(ids: match.assetIDs)
    guard self.isCurrent(generation), !Task.isCancelled else { return .stale }
    let captures = try await photoStore.assets(in: Set(TripDetail.captureCategories), createdIn: period.captureInterval)
    let detail = TripDetail(
      trip: match,
      period: period,
      mapCenter: key?.coordinate,
      photos: photos,
      // 저장소는 최신순이라 촬영순으로 뒤집는다.
      captureGroups: TripDetail.captureCategories.compactMap { category in
        guard let assets = captures[category], !assets.isEmpty else { return nil }
        return TripCaptureGroup(category: category, assets: assets.reversed())
      }
    )
    return .found(detail, cachedName: cached?.name)
  }

  /// 캐시에 이름이 있으면 그것을 쓴다. 없으면 이 방문에서 그 키로 받은 결과를 다시 쓰고, 처음 보는 키는 묻고, 묻는 중이던 키는
  /// 진행 중 요청을 이어받거나 다시 묻는다. 이름은 늘 지금 키·로캘의 값이다.
  private func updatePlaceName(key: RoundedCoordinate?, cached: CachedPlaceName?, localeIdentifier: String) {
    guard let key else {
      self.setPlaceName(.unavailable, for: nil)
      return
    }
    let request = TripPlaceRequest(key: key, localeIdentifier: localeIdentifier)
    if let cached {
      let state = cached.state
      self.visitPlaces[request] = state
      self.setPlaceName(state, for: request)
      return
    }
    switch self.visitPlaces[request] {
    case nil:
      // 이 방문에서 처음 보는 키.
      self.visitPlaces[request] = .loading
      self.setPlaceName(.loading, for: request)
      self.placeRequests?.yield(request)
    case .loading:
      // 결과를 받을 쪽이 없었거나(사진 상세에 다녀옴, 기다림을 멈춤) 묻는 중이다. 진행 중 요청을 이어받거나 다시 묻는다.
      self.setPlaceName(.loading, for: request)
      self.placeRequests?.yield(request)
    case let known?:
      // 이 방문에서 이미 결과를 받았다(캐시는 replaceTrips 가 지웠거나 항목 없음·실패라 없다). 다시 묻지 않는다.
      self.setPlaceName(known, for: request)
    }
  }
}

// MARK: - Place name

extension TripDetailModel {
  /// 이름 요청을 받아 기다린다. 다시 읽기와 따로 돌아, 기다리는 동안에도 다시 읽기가 내용을 바꾼다. 다른 요청이 오면 지난 키의
  /// 기다림을 멈추고(요청은 끝까지 가서 캐시에 쓴다) 바로 기다리고, 같은 요청을 기다리는 중에 온 신호는 건너뛴다.
  private func runPlaceRequests(
    _ requests: AsyncStream<TripPlaceRequest>,
    photoStore: any PhotoStoreClient,
    generation: Int
  ) async {
    var waiting: Task<Void, Never>?
    for await request in requests {
      guard self.isCurrent(generation) else { break }
      if let current = self.waitingPlace, current.generation == generation, current.request == request {
        continue
      }
      waiting?.cancel()
      self.waitingPlaceCount += 1
      let token = self.waitingPlaceCount
      self.waitingPlace = TripPlaceWait(generation: generation, token: token, request: request)
      waiting = Task { @MainActor in
        await self.resolvePlaceName(request, photoStore: photoStore, generation: generation)
        if self.waitingPlace?.token == token {
          self.waitingPlace = nil
        }
      }
    }
    // 화면이 닫히면 기다림을 멈춘다.
    waiting?.cancel()
  }

  /// 이름을 묻고 응답이나 시한 중 먼저 오는 것을 반영한다. 기다림이 멈추면(화면이 닫힘, 키·로캘이 바뀜) 아무것도 바꾸지 않고
  /// 요청은 끝까지 가서 캐시에 쓴다. 같은 진입에서 받은 결과는 키·로캘이 바뀌었어도 그 요청의 결과로 기억하고, 이름에는 반영하지 않는다.
  private func resolvePlaceName(_ request: TripPlaceRequest, photoStore: any PhotoStoreClient, generation: Int) async {
    // 지금 이름의 주인(키·로캘)이 아니거나 이 방문에서 이미 결과를 받은 요청이면 묻지 않는다.
    guard !Task.isCancelled, self.placeNameRequest == request,
          self.visitPlaces[request] == .loading else { return }
    let inFlight = self.sharedOrNewRequest(request, photoStore: photoStore)
    let outcome = await TripPlaceOutcome.first(of: inFlight.task, until: inFlight.startedAt + self.placeNameTimeout)
    guard let outcome, self.isCurrent(generation), !Task.isCancelled else { return }
    let state: TripPlaceNameState = switch outcome {
    case let .found(info): info?.name.map { .named($0) } ?? .unnamed
    case .failed: .unavailable
    }
    self.visitPlaces[request] = state
    guard self.placeNameRequest == request else { return }
    self.setPlaceName(state, for: request)
    // 시간대를 받았으면 다시 읽어 캐시의 시간대로 기간·캡처를 다시 계산한다. 항목이 없으면(nil) 캐시가 없어 대체 규칙 그대로다.
    if case let .found(info) = outcome, info?.timeZoneIdentifier != nil {
      self.reloadRequests?.yield()
    }
  }

  /// 같은 키·로캘의 요청이 시한 안이면 이어받고, 아니면 새로 묻는다.
  private func sharedOrNewRequest(_ request: TripPlaceRequest, photoStore: any PhotoStoreClient) -> TripPlaceInFlight {
    if let inFlight = self.inFlights[request], ContinuousClock.now < inFlight.startedAt + self.placeNameTimeout {
      return inFlight
    }
    self.inFlightCount += 1
    let token = self.inFlightCount
    let map = self.map
    // 받은 Task 가 취소돼도 요청은 끝까지 가므로(`MapClient`), 화면 수명과 떨어진 Task 로 묻는다.
    let task = Task { @MainActor in
      let outcome: TripPlaceOutcome
      do throws(PlaceNameError) {
        let info = try await map.placeName(near: request.key, locale: Locale(identifier: request.localeIdentifier))
        // 항목이 없으면(placemarkNotFound) 캐시하지 않는다. 오프라인에서도 올 수 있어 굳으면 회복할 수 없다.
        if let info {
          let saved = await (try? photoStore.savePlace(
            info.name.map { .named($0) } ?? .unnamed,
            timeZoneIdentifier: info.timeZoneIdentifier,
            for: request.key,
            localeIdentifier: request.localeIdentifier
          )) ?? false
          // 시한 뒤에 늦게 성공해도 열려 있는 화면이 캐시 이름·시간대를 반영하게 다시 읽는다.
          // 이어받은 요청은 만든 진입과 번호가 달라 번호는 보지 않는다. 닫혀 있으면 신호가 없어 아무 일도 없다.
          if saved, self.currentTrip?.placeKey == request.key {
            self.reloadRequests?.yield()
          }
        }
        outcome = .found(info)
      } catch {
        outcome = .failed
      }
      if self.inFlights[request]?.token == token {
        self.inFlights[request] = nil
      }
      return outcome
    }
    let inFlight = TripPlaceInFlight(token: token, request: request, startedAt: .now, task: task)
    self.inFlights[request] = inFlight
    return inFlight
  }

  // MARK: - Private

  /// 이름을 바꾸는 유일한 길. 이름과 그 주인을 함께 바꾸고, 같으면 대입하지 않아 다시 그리지 않는다.
  private func setPlaceName(_ state: TripPlaceNameState, for request: TripPlaceRequest?) {
    self.placeNameRequest = request
    if self.placeName != state {
      self.placeName = state
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
