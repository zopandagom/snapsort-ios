import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 상세의 장소 이름: 캐시, 요청 시점·횟수, 응답 종류, 시한. 닫힘·재진입은 `TripDetailPlaceNameReentryTests`.
/// 응답을 붙잡을 때는 `MapClientFake.onPlaceName` 에 `CallGates` 를 쓴다. 끝나지 않는 응답은 취소에도 풀리지 않는 문으로 흉내 내고
/// 테스트 끝에서 연다.
@MainActor
struct TripDetailPlaceNameTests {
  @Test("화면을 열기 전에는 묻지 않는다")
  func noRequestBeforeAppear() async {
    let map = MapClientFake()
    let model = TripFixture.detailModel(photoStore: TripFixture.tokyoStore(), map: map)
    await settle()
    #expect(map.placeNameRequests.isEmpty)
    #expect(model.placeName == .loading)
  }

  @Test("지금 로캘로 캐시된 이름이 있으면 묻지 않고 바로 보인다")
  func cachedNameNeedsNoRequest() async {
    let map = MapClientFake()
    let photoStore = TripFixture.tokyoStore(places: [TripFixture.tokyoKey: CachedPlace(
      name: .named("도쿄"),
      timeZoneIdentifier: "Asia/Tokyo"
    )])
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .named("도쿄") }
    await settle()
    #expect(map.placeNameRequests.isEmpty)
    await cancelAndWait(appear)
  }

  @Test("캐시가 없으면 반올림 키와 지금 로캘로 한 번 묻고, 이름·시간대를 캐시하고 이름을 보인다")
  func uncachedNameIsRequestedAndSaved() async {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)])
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }

    #expect(map.placeNameRequests == [PlaceNameRequest(coordinate: TripFixture.tokyoKey, localeIdentifier: "ko_KR")])
    #expect(photoStore.savedPlaces == [SavedPlace(
      key: TripFixture.tokyoKey,
      localeIdentifier: "ko_KR",
      name: .named("일본 도쿄 지요다구"),
      timeZoneIdentifier: "Asia/Tokyo"
    )])
    await cancelAndWait(appear)
  }

  @Test("시간대를 받으면 다시 읽어 기간을 여행지 시간대로 다시 계산한다")
  func receivedTimeZoneRecomputesPeriod() async {
    let gates = CallGates(holding: [0])
    let mapHeld = MapClientFake(
      placeNameResults: [TripFixture.newYorkKey: .success(PlaceInfo(
        name: "뉴욕",
        timeZoneIdentifier: "America/New_York"
      ))],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.newYork),
      trips: [TripFixture.newYork]
    )
    let model = TripFixture.detailModel(photoStore: photoStore, map: mapHeld)
    let appear = openDetail(model, trip: TripFixture.newYork, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    // 알려진 한계 (a): 시간대를 모르는 동안은 마지막 날이 하루 이르다.
    #expect(model.content.detail?.period.lastDay == .date(2026, 7, 14))

    gates.open(0)
    await waitUntil { model.content.detail?.period.isTimeZoneKnown == true }
    #expect(model.content.detail?.period.lastDay == .date(2026, 7, 15))
    #expect(model.placeName == .named("뉴욕"))
    await cancelAndWait(appear)
  }

  @Test("쓸 이름 필드가 없는 응답은 이름 없음으로 보이고 이름 없음으로 캐시한다")
  func unnamedResponseIsCached() async {
    let map = MapClientFake(placeNameResults: [
      TripFixture.tokyoKey: .success(PlaceInfo(name: nil, timeZoneIdentifier: "Asia/Tokyo")),
    ])
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unnamed }
    await waitUntil { photoStore.savedPlaces.map(\.name) == [.unnamed] }
    await cancelAndWait(appear)
  }

  @Test("항목이 없으면(placemarkNotFound) 이름 없음으로 보이고 캐시하지 않는다")
  func notFoundResponseIsNotCached() async {
    let map = MapClientFake()
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unnamed }
    await settle()
    #expect(photoStore.savedPlaces.isEmpty)
    await cancelAndWait(appear)
  }

  @Test("요청이 실패하면 이름을 못 찾음으로 보이고 캐시하지 않는다")
  func failedRequestShowsUnavailable() async {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .failure(.failed)])
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unavailable }
    #expect(photoStore.savedPlaces.isEmpty)
    #expect(model.content.detail != nil)
    await cancelAndWait(appear)
  }

  @Test("같은 방문에서 다시 읽기 신호가 여러 번 와도 풀린 이름은 다시 묻지 않는다")
  func reloadSignalsDoNotRequestResolvedName() async {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .failure(.failed)])
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unavailable }

    let callCount = photoStore.tripsCallCount
    model.libraryStoreChanged()
    await waitUntil { photoStore.tripsCallCount == callCount + 1 }
    model.libraryStoreChanged()
    await waitUntil { photoStore.tripsCallCount == callCount + 2 }
    model.dayChanged()
    await waitUntil { photoStore.tripsCallCount == callCount + 3 }
    await settle()
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(appear)
  }

  @Test("다른 로캘로 캐시된 이름은 지금 로캘로 다시 묻는다")
  func otherLocaleCacheIsRequested() async {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)])
    let photoStore = TripFixture.tokyoStore(
      places: [TripFixture.tokyoKey: CachedPlace(name: .named("Chiyoda, Tokyo"), timeZoneIdentifier: "Asia/Tokyo")],
      placesLocaleIdentifier: "en_US"
    )
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    #expect(map.placeNameRequests.map(\.localeIdentifier) == ["ko_KR"])
    await cancelAndWait(appear)
  }

  @Test("캐시를 읽지 못하면 내용이 실패이고 이름은 묻지 않는다")
  func cacheReadFailureRequestsNothing() async {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.tokyo],
      placeError: .failed
    )
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.content == .failed }
    await settle()
    #expect(map.placeNameRequests.isEmpty)
    await cancelAndWait(appear)
  }

  @Test("응답이 시한을 넘기면 못 찾음으로 보인다")
  func timeoutShowsUnavailable() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(onPlaceName: { await gates.pass($0) })
    let model = TripFixture.detailModel(
      photoStore: TripFixture.tokyoStore(),
      map: map,
      placeNameTimeout: .milliseconds(200)
    )
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unavailable }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(appear)
  }

  @Test("시한 뒤 늦게 성공하면 새 신호 없이 다시 읽어 캐시 이름과 시간대를 반영한다")
  func lateSuccessAfterTimeoutIsReflected() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.newYorkKey: .success(PlaceInfo(
        name: "뉴욕",
        timeZoneIdentifier: "America/New_York"
      ))],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.newYork),
      trips: [TripFixture.newYork]
    )
    let model = TripFixture.detailModel(photoStore: photoStore, map: map, placeNameTimeout: .milliseconds(200))
    let appear = openDetail(model, trip: TripFixture.newYork, visit: UUID())
    await waitUntil { model.placeName == .unavailable }
    #expect(model.content.detail?.period.lastDay == .date(2026, 7, 14))

    gates.open(0)
    await waitUntil { model.placeName == .named("뉴욕") }
    await waitUntil { model.content.detail?.period.lastDay == .date(2026, 7, 15) }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(appear)
  }

  @Test("판정이 바뀌어도 중심점 키가 같으면 다시 묻지 않고, 키가 바뀌면 새 키로 한 번 묻는다")
  func rejudgedTripRequestsOnlyNewKey() async throws {
    let map = MapClientFake()
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unnamed }

    let sameKey = Trip(
      assetIDs: TripFixture.tokyo.assetIDs.dropLast(),
      startDate: TripFixture.tokyo.startDate,
      endDate: TripFixture.tokyo.endDate,
      center: Coordinate(latitude: 35.6801, longitude: 139.7598)
    )
    try await photoStore.replaceTrips([sameKey])
    model.libraryStoreChanged()
    await waitUntil { model.content.detail?.trip == sameKey }
    await settle()
    #expect(map.placeNameRequests.count == 1)

    let movedCenter = Coordinate(latitude: 35.0116, longitude: 135.7681)
    let moved = Trip(
      assetIDs: TripFixture.tokyo.assetIDs,
      startDate: TripFixture.tokyo.startDate,
      endDate: TripFixture.tokyo.endDate,
      center: movedCenter
    )
    try await photoStore.replaceTrips([moved])
    model.libraryStoreChanged()
    await waitUntil { map.placeNameRequests.count == 2 }
    #expect(map.placeNameRequests.last?.coordinate == RoundedCoordinate(movedCenter))
    await waitUntil { model.placeName == .unnamed }
    await cancelAndWait(appear)
  }
}
