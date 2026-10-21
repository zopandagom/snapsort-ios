import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 한 방문 안에서 판정이 중심점 키를 A(제주) → B(도쿄) → A 로 바꿨다 되돌릴 때의 장소 이름.
/// 키가 바뀐 판정의 `replaceTrips` 가 지난 키의 캐시를 지우므로, 되돌린 키는 이 방문에서 받은 결과를 다시 쓴다.
@MainActor
struct TripDetailPlaceNameKeyTests {
  /// 제주 여행과 사진이 같고 중심점만 도쿄인 판정.
  private static let movedTrip = Trip(
    assetIDs: TripFixture.jeju.assetIDs,
    startDate: TripFixture.jeju.startDate,
    endDate: TripFixture.jeju.endDate,
    center: TripFixture.tokyoCenter
  )
  private static let jejuInfo = PlaceInfo(name: "제주", timeZoneIdentifier: "Asia/Seoul")

  private static func store(places: [RoundedCoordinate: CachedPlace] = [:]) -> PhotoStoreClientFake {
    PhotoStoreClientFake(images: TripFixture.photos(of: TripFixture.jeju), trips: [TripFixture.jeju], places: places)
  }

  /// 판정을 `trip` 하나로 바꾸고 다시 읽어 그 여행이 보일 때까지 기다린다.
  private static func rejudge(
    to trip: Trip,
    photoStore: PhotoStoreClientFake,
    model: TripDetailModel
  ) async throws {
    try await photoStore.replaceTrips([trip])
    model.libraryStoreChanged()
    await waitUntil { model.content.detail?.trip == trip }
  }

  private static func requestCount(_ map: MapClientFake, _ key: RoundedCoordinate) -> Int {
    map.placeNameRequests.count { $0.coordinate == key }
  }

  /// 내용이 보이면 이름의 주인 키는 보이는 여행의 키다.
  private static func expectNameBelongsToContent(_ model: TripDetailModel) {
    if let detail = model.content.detail {
      #expect(model.placeNameRequest?.key == detail.trip.placeKey)
    }
  }

  @Test("받은 이름의 키로 되돌아오면 캐시가 지워졌어도 그 이름을 다시 보이고 다시 묻지 않는다")
  func returningKeyReusesReceivedName() async throws {
    let map = MapClientFake(placeNameResults: [
      TripFixture.jejuKey: .success(Self.jejuInfo),
      TripFixture.tokyoKey: .success(TripFixture.tokyoInfo),
    ])
    let photoStore = Self.store()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.placeName == .named("제주") }
    Self.expectNameBelongsToContent(model)

    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    let jejuCache = try await photoStore.places(for: [TripFixture.jejuKey], localeIdentifier: "ko_KR")
    #expect(jejuCache.isEmpty)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    Self.expectNameBelongsToContent(model)

    try await Self.rejudge(to: TripFixture.jeju, photoStore: photoStore, model: model)
    await waitUntil { model.placeName == .named("제주") }
    #expect(model.placeNameRequest?.key == TripFixture.jejuKey)
    Self.expectNameBelongsToContent(model)
    await settle()
    #expect(Self.requestCount(map, TripFixture.jejuKey) == 1)
    #expect(Self.requestCount(map, TripFixture.tokyoKey) == 1)
    await cancelAndWait(appear)
  }

  @Test("실패를 보인 키로 되돌아오면 묻는 중이던 다른 키의 상태 대신 못 찾음을 보이고 다시 묻지 않는다")
  func returningFailedKeyKeepsUnavailable() async throws {
    // 0 제주(실패), 1 도쿄(붙잡음).
    let gates = CallGates(holding: [1], ignoresCancellation: true)
    defer { gates.open(1) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.jejuKey: .failure(.failed), TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = Self.store()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.placeName == .unavailable }

    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    await waitUntil { gates.hasEntered(1) }
    #expect(model.placeName == .loading)

    try await Self.rejudge(to: TripFixture.jeju, photoStore: photoStore, model: model)
    #expect(model.placeName == .unavailable)
    Self.expectNameBelongsToContent(model)

    // 도쿄 응답이 늦게 와도 제주 이름을 바꾸지 않고, 도쿄 여행이 없어 캐시되지 않는다.
    // 제주는 결과를 기억해 새 요청을 넣지 않으므로 도쿄의 기다림은 이어지고, 받은 결과는 이 방문의 도쿄 결과로 기억한다.
    gates.open(1)
    await settle()
    #expect(model.placeName == .unavailable)
    #expect(photoStore.savedPlaces.isEmpty)
    #expect(Self.requestCount(map, TripFixture.jejuKey) == 1)

    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    #expect(model.placeName == .named("일본 도쿄 지요다구"))
    await settle()
    #expect(Self.requestCount(map, TripFixture.tokyoKey) == 1)
    await cancelAndWait(appear)
  }

  @Test("실패를 보인 키에서 캐시가 있는 키로 갔다 되돌아와도 못 찾음을 쓰고 요청이 늘지 않는다")
  func returningFromCachedKeyKeepsUnavailable() async throws {
    let map = MapClientFake(placeNameResults: [TripFixture.jejuKey: .failure(.failed)])
    let photoStore = Self.store(places: [
      TripFixture.tokyoKey: CachedPlace(name: .named("도쿄"), timeZoneIdentifier: "Asia/Tokyo"),
    ])
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.placeName == .unavailable }

    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    await waitUntil { model.placeName == .named("도쿄") }

    try await Self.rejudge(to: TripFixture.jeju, photoStore: photoStore, model: model)
    #expect(model.placeName == .unavailable)
    Self.expectNameBelongsToContent(model)
    await settle()
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(appear)
  }

  @Test("묻는 중에 키가 바뀌면 지난 키의 응답을 기다리지 않고 새 키를 바로 묻고, 되돌아오면 진행 중 요청을 이어받는다")
  func keyChangeDoesNotWaitForPreviousKey() async throws {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [
        TripFixture.jejuKey: .success(Self.jejuInfo),
        TripFixture.tokyoKey: .success(TripFixture.tokyoInfo),
      ],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = Self.store()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { gates.hasEntered(0) }

    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    // 제주 응답(붙잡힘)을 기다리지 않고 도쿄 이름이 보인다.
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }

    try await Self.rejudge(to: TripFixture.jeju, photoStore: photoStore, model: model)
    #expect(model.placeName == .loading)
    await settle()
    #expect(Self.requestCount(map, TripFixture.jejuKey) == 1)

    gates.open(0)
    await waitUntil { model.placeName == .named("제주") }
    #expect(Self.requestCount(map, TripFixture.jejuKey) == 1)
    await cancelAndWait(appear)
  }

  @Test("항목이 없던 키로 되돌아오면 이름 없음을 다시 쓰고 다시 묻지 않는다")
  func returningNotFoundKeyKeepsUnnamed() async throws {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)])
    let photoStore = Self.store()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.placeName == .unnamed }

    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }

    try await Self.rejudge(to: TripFixture.jeju, photoStore: photoStore, model: model)
    #expect(model.placeName == .unnamed)
    await settle()
    #expect(Self.requestCount(map, TripFixture.jejuKey) == 1)
    await cancelAndWait(appear)
  }

  @Test("목록에서 새로 열면 지난 방문의 기억을 비워, 캐시가 없는 키를 한 번 다시 묻는다")
  func newVisitForgetsReceivedNames() async throws {
    let map = MapClientFake(placeNameResults: [
      TripFixture.jejuKey: .success(Self.jejuInfo),
      TripFixture.tokyoKey: .success(TripFixture.tokyoInfo),
    ])
    let photoStore = Self.store()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.placeName == .named("제주") }
    try await Self.rejudge(to: Self.movedTrip, photoStore: photoStore, model: model)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    try await Self.rejudge(to: TripFixture.jeju, photoStore: photoStore, model: model)
    await waitUntil { model.placeName == .named("제주") }
    await cancelAndWait(first)

    let reopened = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { Self.requestCount(map, TripFixture.jejuKey) == 2 }
    await waitUntil { model.placeName == .named("제주") }
    await cancelAndWait(reopened)
  }
}
