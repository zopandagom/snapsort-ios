import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 판정이 여행을 나눈 뒤 새로 연 여행과 지난 방문의 진행 중 이름 요청의 겹침(`TripDetailVisitTests` 의 나뉜 여행 A·B·C).
@MainActor
struct TripDetailVisitPlaceNameTests {
  @Test("지난 방문의 진행 중 이름 요청이 늦게 끝나도 새로 연 다른 여행의 이름·내용을 바꾸지 않고 캐시에만 쓴다")
  func previousVisitRequestDoesNotLeakIntoNewTrip() async throws {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [
        TripFixture.jejuKey: .success(PlaceInfo(name: "제주", timeZoneIdentifier: "Asia/Seoul")),
        TripFixture.tokyoKey: .success(TripFixture.tokyoInfo),
      ],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = TripFixture.splitStore(places: [:])
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let first = openDetail(model, trip: TripFixture.splitA, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    try await photoStore.replaceTrips([TripFixture.splitB, TripFixture.splitC])
    let second = openDetail(model, trip: TripFixture.splitC, visit: UUID())
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    // 받은 시간대로 다시 읽기가 끝나 기간이 여행지 시간대가 된 뒤를 기준으로 센다.
    await waitUntil { model.content.detail?.period.isTimeZoneKnown == true }
    await settle()
    let callCount = photoStore.tripsCallCount
    let content = model.content

    gates.open(0)
    await waitUntil { photoStore.savedPlaces.contains { $0.key == TripFixture.jejuKey } }
    await settle()
    #expect(model.placeName == .named("일본 도쿄 지요다구"))
    #expect(model.content == content)
    #expect(photoStore.tripsCallCount == callCount)
    #expect(map.placeNameRequests.count == 2)
    await cancelAndWait(second)
  }

  @Test("새로 연 여행의 키가 지난 방문의 진행 중 요청과 같으면 그 요청을 이어받아 더 묻지 않는다")
  func newTripWithSameKeySharesPreviousRequest() async throws {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let map = MapClientFake(
      placeNameResults: [TripFixture.jejuKey: .success(PlaceInfo(name: "제주", timeZoneIdentifier: "Asia/Seoul"))],
      onPlaceName: { await gates.pass($0) }
    )
    let sameKeyC = Trip(
      assetIDs: TripFixture.splitC.assetIDs,
      startDate: TripFixture.splitC.startDate,
      endDate: TripFixture.splitC.endDate,
      center: TripFixture.jejuCenter
    )
    let photoStore = TripFixture.splitStore(places: [:])
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let first = openDetail(model, trip: TripFixture.splitA, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    try await photoStore.replaceTrips([TripFixture.splitB, sameKeyC])
    let second = openDetail(model, trip: sameKeyC, visit: UUID())
    await waitUntil { model.content.detail?.trip == sameKeyC }
    await settle()
    #expect(model.placeName == .loading)

    gates.open(0)
    await waitUntil { model.placeName == .named("제주") }
    #expect(map.placeNameRequests.count == 1)
    await cancelAndWait(second)
  }
}
