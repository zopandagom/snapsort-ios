import Core
import Foundation
import MapInterface
import MapTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 상세의 장소 이름: 닫힘·재진입(같은 visit = 사진 상세에서 돌아옴, 새 visit = 목록에서 다시 엶)과 진행 중 요청 이어받기.
/// 응답을 붙잡을 때는 `MapClientFake.onPlaceName` 에 `CallGates` 를 쓴다. 끝나지 않는 응답은 취소에도 풀리지 않는 문으로 흉내 내고
/// 테스트 끝에서 연다.
@MainActor
struct TripDetailPlaceNameReentryTests {
  @Test("실패를 보인 뒤 사진 상세에서 돌아오면(같은 visit) 다시 묻지 않고, 목록에서 새로 열면 한 번 다시 묻는다")
  func failedNameIsRetriedOnlyOnNewVisit() async {
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .failure(.failed)])
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { model.placeName == .unavailable }
    await cancelAndWait(first)

    let callCount = photoStore.tripsCallCount
    let back = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { photoStore.tripsCallCount == callCount + 1 }
    await settle()
    #expect(map.placeNameRequests.count == 1)
    #expect(model.placeName == .unavailable)
    await cancelAndWait(back)

    // 진행 중 요청이 실패로 끝나면 비워져, 새 방문은 공유하지 않고 새로 묻는다.
    let reopened = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { map.placeNameRequests.count == 2 }
    await waitUntil { model.placeName == .unavailable }
    await cancelAndWait(reopened)
  }

  @Test("항목이 없어 캐시하지 않은 이름은 같은 방문에서는 다시 묻지 않고, 새 방문에서 한 번 다시 묻는다")
  func notFoundNameIsRetriedOnNewVisit() async {
    let map = MapClientFake()
    let model = TripFixture.detailModel(photoStore: TripFixture.tokyoStore(), map: map)
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { model.placeName == .unnamed }
    await cancelAndWait(first)

    let back = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await settle()
    await waitUntil { model.content.detail != nil }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(back)

    let reopened = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { map.placeNameRequests.count == 2 }
    await cancelAndWait(reopened)
  }

  @Test("닫은 뒤 늦게 끝난 응답은 상태를 바꾸지 않고 캐시에만 쓰며, 다시 열면 묻지 않고 캐시 이름을 보인다")
  func lateResponseAfterCloseIsOnlyCached() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = TripFixture.tokyoStore()
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let first = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    gates.open(0)
    await waitUntil { photoStore.savedPlaces.count == 1 }
    await settle()
    #expect(model.placeName == .loading)

    let reopened = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(reopened)
  }

  @Test("묻는 중에 닫고 목록에서 다시 열면(새 visit) 진행 중 요청을 이어받아 한 번만 묻는다")
  func newVisitSharesInFlightRequest() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: TripFixture.tokyoStore(), map: map)
    let first = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let reopened = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.content.detail != nil }
    await settle()
    gates.open(0)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(reopened)
  }

  @Test("묻는 중에 사진 상세에 갔다 돌아오면(같은 visit) 진행 중 요청을 이어받아 이름이 보이고 한 번만 묻는다")
  func sameVisitSharesInFlightRequest() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: TripFixture.tokyoStore(), map: map)
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let back = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { model.content.detail != nil }
    await settle()
    #expect(model.placeName == .loading)
    gates.open(0)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(back)
  }

  @Test("사진 상세에 가 있는 동안 요청이 실패했으면, 같은 visit 으로 돌아와 한 번 다시 묻고 그 결과로 끝난다")
  func sameVisitRetriesRequestFailedWhileClosed() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .failure(.failed)],
      onPlaceName: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: TripFixture.tokyoStore(), map: map)
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)
    gates.open(0)
    // 실패한 요청이 끝나 진행 중 요청을 비울 때까지 양보한다(앱이 드러내는 신호가 없다).
    await settle()
    #expect(model.placeName == .loading)

    let back = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { model.placeName == .unavailable }
    #expect(map.placeNameRequests.count == 2)
    await cancelAndWait(back)
  }

  @Test("사진 상세에 가 있는 동안 시한을 넘겼으면, 같은 visit 으로 돌아와 새로 한 번 묻고 시한 뒤 못 찾음으로 끝난다")
  func sameVisitRetriesRequestTimedOutWhileClosed() async throws {
    let gates = CallGates(holding: [0, 1], ignoresCancellation: true)
    defer {
      gates.open(0)
      gates.open(1)
    }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(
      photoStore: TripFixture.tokyoStore(),
      map: map,
      placeNameTimeout: .milliseconds(200)
    )
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)
    try await Task.sleep(for: .milliseconds(300))

    let back = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { gates.hasEntered(1) }
    await waitUntil { model.placeName == .unavailable }
    #expect(map.placeNameRequests.count == 2)
    await cancelAndWait(back)
  }

  @Test("같은 visit 으로 돌아와 이어받은 요청이 시한을 넘긴 뒤 늦게 성공해도 이름이 보인다")
  func lateSuccessOfSharedRequestIsReflected() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    // 닫고 다시 여는 동안 시한이 지나지 않을 만큼 둔다.
    let model = TripFixture.detailModel(photoStore: TripFixture.tokyoStore(), map: map, placeNameTimeout: .seconds(1))
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let back = openDetail(model, trip: TripFixture.tokyo, visit: visit)
    await waitUntil { model.placeName == .unavailable }
    #expect(map.placeNameRequests.count == 1)

    gates.open(0)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(back)
  }

  @Test("시한이 지난 진행 중 요청은 새 방문에서 이어받지 않고 새로 한 번 묻는다")
  func expiredInFlightIsNotShared() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)],
      onPlaceName: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(
      photoStore: TripFixture.tokyoStore(),
      map: map,
      placeNameTimeout: .milliseconds(200)
    )
    let first = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .unavailable }
    await cancelAndWait(first)

    let reopened = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    #expect(map.placeNameRequests.count == 2)
    await cancelAndWait(reopened)
  }
}
