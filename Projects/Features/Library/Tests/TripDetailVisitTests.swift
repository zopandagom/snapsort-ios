import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 상세의 기준 여행과 visit: 새 방문은 누른 여행을, 같은 방문은 마지막으로 찾은 여행을 기준으로 삼는다.
/// 판정이 여행을 나누거나 옮긴 뒤 다시 열 때 지난 여행의 내용·이름이 남지 않는지 본다.
@MainActor
struct TripDetailVisitTests {
  @Test("판정이 여행을 나눈 뒤 작은 쪽을 새로 열면 불러오는 중을 거쳐 그 여행의 내용·지도·이름을 보인다")
  func splitSmallerSideShowsItsOwnTrip() async throws {
    let gates = CallGates(holding: [1])
    let map = MapClientFake(placeNameResults: [TripFixture.tokyoKey: .success(TripFixture.tokyoInfo)])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.splitA),
      trips: [TripFixture.splitA],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let first = openDetail(model, trip: TripFixture.splitA, visit: UUID())
    await waitUntil { model.placeName == .named("제주특별자치도 제주시") }
    await cancelAndWait(first)

    try await photoStore.replaceTrips([TripFixture.splitB, TripFixture.splitC])
    let visit = UUID()
    let second = openDetail(model, trip: TripFixture.splitC, visit: visit)
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == .loading)
    #expect(model.placeName == .loading)
    #expect(model.visit == visit)

    gates.open(1)
    await waitUntil { model.placeName == .named("일본 도쿄 지요다구") }
    let detail = model.content.detail
    #expect(detail?.trip == TripFixture.splitC)
    #expect(detail?.mapCenter == TripFixture.tokyoKey.coordinate)
    #expect(detail?.period.firstDay == .date(2026, 7, 13))
    #expect(detail?.photos.map(\.id) == Array(TripFixture.splitIDs.suffix(3)))
    #expect(map.placeNameRequests.map(\.coordinate) == [TripFixture.tokyoKey])
    await cancelAndWait(second)
  }

  @Test("판정이 여행을 나눈 뒤 큰 쪽을 새로 열면 지난 값과 달라 불러오는 중을 거쳐 그 여행을 보인다")
  func splitLargerSideShowsItsOwnTrip() async throws {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.splitA),
      trips: [TripFixture.splitA],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.splitA, visit: UUID())
    await waitUntil { model.content.detail != nil }
    await cancelAndWait(first)

    try await photoStore.replaceTrips([TripFixture.splitB, TripFixture.splitC])
    let second = openDetail(model, trip: TripFixture.splitB, visit: UUID())
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == .loading)

    gates.open(1)
    await waitUntil { model.content.detail?.trip == TripFixture.splitB }
    await cancelAndWait(second)
  }

  @Test("목록에서 같은 여행 값을 새로 열면 지난 내용·이름을 둔 채 다시 읽는다")
  func sameValueNewVisitKeepsContent() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail != nil }
    let loaded = model.content
    await cancelAndWait(first)

    let visit = UUID()
    let second = openDetail(model, trip: TripFixture.jeju, visit: visit)
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == loaded)
    #expect(model.placeName == .named("제주특별자치도 제주시"))
    #expect(model.visit == visit)

    gates.open(1)
    await cancelAndWait(second)
  }

  @Test("목록에서 같은 여행 값을 새로 열면 처음 읽기 실패는 불러오는 중을 거쳐 내용이 된다")
  func sameValueNewVisitAfterFailure() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      tripsErrors: [0: .failed],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content == .failed }
    await cancelAndWait(first)

    let second = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == .loading)
    gates.open(1)
    await waitUntil { model.content.detail?.trip == TripFixture.jeju }
    await cancelAndWait(second)
  }

  @Test("목록에서 같은 여행 값을 새로 열면 찾을 수 없음은 둔 채 다시 읽고, 여행이 돌아왔으면 내용이 된다")
  func sameValueNewVisitAfterNotFound() async throws {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.tokyo],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content == .notFound }
    await cancelAndWait(first)

    try await photoStore.replaceTrips([TripFixture.jeju, TripFixture.tokyo])
    let second = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == .notFound)
    gates.open(1)
    await waitUntil { model.content.detail?.trip == TripFixture.jeju }
    await cancelAndWait(second)
  }

  @Test("같은 방문 동안 판정이 바뀌어 처음 여행과 사진이 겹치지 않게 돼도, 사진 상세에서 돌아오면 마지막으로 찾은 여행을 그대로 보인다")
  func sameVisitKeepsLastMatch() async throws {
    let first3 = Trip(
      assetIDs: ["m-1", "m-2", "m-3"],
      startDate: .seoul(2026, 7, 10, hour: 9),
      endDate: .seoul(2026, 7, 10, hour: 18),
      center: TripFixture.jejuCenter
    )
    let middle = Trip(
      assetIDs: ["m-3", "m-4", "m-5"],
      startDate: .seoul(2026, 7, 10, hour: 9),
      endDate: .seoul(2026, 7, 10, hour: 18),
      center: TripFixture.jejuCenter
    )
    let last = Trip(
      assetIDs: ["m-5", "m-6", "m-7"],
      startDate: .seoul(2026, 7, 10, hour: 9),
      endDate: .seoul(2026, 7, 10, hour: 18),
      center: TripFixture.jejuCenter
    )
    // 처음 읽기 0, 신호 두 번 1·2, 돌아온 뒤 3.
    let gates = CallGates(holding: [3])
    let images = (1 ... 7).map { IndexedImage.dated(
      id: "m-\($0)",
      .seoul(2026, 7, 10, hour: 9 + $0),
      categories: [.landscape]
    ) }
    let photoStore = PhotoStoreClientFake(
      images: images,
      trips: [first3],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let visit = UUID()
    let first = openDetail(model, trip: first3, visit: visit)
    await waitUntil { model.content.detail?.trip == first3 }

    try await photoStore.replaceTrips([middle])
    model.libraryStoreChanged()
    await waitUntil { model.content.detail?.trip == middle }
    try await photoStore.replaceTrips([last])
    model.libraryStoreChanged()
    await waitUntil { model.content.detail?.trip == last }
    await cancelAndWait(first)

    // 화면 인스턴스는 처음 누른 여행을 route 로 들고 있다.
    let back = openDetail(model, trip: first3, visit: visit)
    await waitUntil { gates.hasEntered(3) }
    #expect(model.content.detail?.trip == last)
    gates.open(3)
    await settle()
    #expect(model.content.detail?.trip == last)
    await cancelAndWait(back)
  }

  @Test("화면이 그릴 visit 은 진입마다 바뀌고, 닫힌 뒤에도 지난 방문의 visit 과 내용이 남아 있다")
  func visitFollowsAppearance() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju, TripFixture.tokyo],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    #expect(model.visit == nil)
    let firstVisit = UUID()
    let first = openDetail(model, trip: TripFixture.jeju, visit: firstVisit)
    await waitUntil { model.content.detail != nil }
    await cancelAndWait(first)
    // 다른 visit 의 화면(`TripDetailView.content`)은 이 내용을 그리지 않고 불러오는 중을 그린다.
    #expect(model.visit == firstVisit)
    #expect(model.content.detail?.trip == TripFixture.jeju)

    let secondVisit = UUID()
    let second = openDetail(model, trip: TripFixture.tokyo, visit: secondVisit)
    await waitUntil { gates.hasEntered(1) }
    #expect(model.visit == secondVisit)
    #expect(model.content == .loading)
    gates.open(1)
    await cancelAndWait(second)
  }
}

extension TripFixture {
  /// 사진 8장인 여행 A. 판정이 A 를 B(앞 5장, 제주 키)·C(뒤 3장, 도쿄 키)로 나눈다.
  static let splitIDs = (0 ..< 8).map { "split-\($0)" }
  static let splitA = Trip(
    assetIDs: TripFixture.splitIDs,
    startDate: .seoul(2026, 7, 10, hour: 9),
    endDate: .seoul(2026, 7, 14, hour: 18),
    center: TripFixture.jejuCenter
  )
  static let splitB = Trip(
    assetIDs: Array(TripFixture.splitIDs.prefix(5)),
    startDate: .seoul(2026, 7, 10, hour: 9),
    endDate: .seoul(2026, 7, 12, hour: 18),
    center: TripFixture.jejuCenter
  )
  static let splitC = Trip(
    assetIDs: Array(TripFixture.splitIDs.suffix(3)),
    startDate: .seoul(2026, 7, 13, hour: 9),
    endDate: .seoul(2026, 7, 14, hour: 18),
    center: TripFixture.tokyoCenter
  )

  static func splitStore(places: [RoundedCoordinate: CachedPlace] = TripFixture.jejuPlace)
    -> PhotoStoreClientFake
  {
    PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.splitA),
      trips: [TripFixture.splitA],
      places: places
    )
  }
}
