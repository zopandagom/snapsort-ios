import Core
import Foundation
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 상세의 내용 읽기·다시 읽기·같은 여행 다시 찾기. 장소 이름은 `TripDetailPlaceNameTests`.
/// 이름 요청이 끼지 않게 대부분 제주 여행에 캐시된 이름을 둔다.
@MainActor
struct TripDetailModelTests {
  @Test("여행 사진과 기간 캡처를 촬영순으로, 캡처는 영수증·지도·문서 순 묶음으로 담고 지워진 사진 수와 반올림 중심점을 둔다")
  func loadsPhotosAndCaptureGroups() async {
    // 시간대를 아는 제주 여행이라 캡처 범위는 [07-10 00:00, 07-13 00:00)(서울)이다.
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju).filter { $0.id != "jeju-3" } + [
        TripFixture.capture("receipt-late", .receipt, at: .seoul(2026, 7, 12, hour: 23, minute: 59)),
        TripFixture.capture("receipt-early", .receipt, at: .seoul(2026, 7, 10, hour: 0)),
        TripFixture.capture("map", .map, at: .seoul(2026, 7, 11, hour: 10)),
        TripFixture.capture("document", .document, at: .seoul(2026, 7, 11, hour: 11)),
        TripFixture.capture("receipt-before", .receipt, at: .seoul(2026, 7, 9, hour: 23, minute: 59)),
        TripFixture.capture("receipt-after", .receipt, at: .seoul(2026, 7, 13, hour: 0)),
        TripFixture.capture("chat", .chat, at: .seoul(2026, 7, 11, hour: 12)),
      ],
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace
    )
    let model = TripFixture.detailModel(photoStore: photoStore)

    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content != .loading }

    let detail = model.content.detail
    #expect(detail?.photos.map(\.id) == ["jeju-0", "jeju-1", "jeju-2"])
    #expect(detail?.missingPhotoCount == 1)
    #expect(detail?.captureGroups.map(\.category) == [.receipt, .map, .document])
    #expect(detail?.captureGroups.map { $0.assets.map(\.id) } == [
      ["receipt-early", "receipt-late"],
      ["map"],
      ["document"],
    ])
    #expect(detail?.mapCenter == TripFixture.jejuKey.coordinate)
    #expect(detail?.period.isTimeZoneKnown == true)
    #expect(model.placeName == .named("제주특별자치도 제주시"))

    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 실패이고 이름은 묻지 않는다")
  func missingStoreShowsFailed() async {
    let map = MapClientFake()
    let model = TripFixture.detailModel(photoStore: nil, map: map)

    await model.onAppear(trip: TripFixture.jeju, visit: UUID())

    #expect(model.content == .failed)
    #expect(model.placeName == .unavailable)
    #expect(map.placeNameRequests.isEmpty)
  }

  @Test("처음 읽지 못하면 실패이고, 다시 시도하면 불러오는 중을 거쳐 내용이 보인다")
  func retryAfterFailureReloads() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      tripsErrors: [0: .failed],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    #expect(model.content == .loading)
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    await waitUntil { model.content.detail?.photos.count == 4 }

    await cancelAndWait(appear)
  }

  @Test("실패가 아니면 다시 시도는 아무것도 하지 않는다")
  func retryIgnoredUnlessFailed() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail != nil }

    model.retryButtonTapped()
    await settle()
    #expect(photoStore.tripsCallCount == 1)

    await cancelAndWait(appear)
  }

  @Test("사진 상세에서 돌아오면(같은 visit) 지난 내용을 둔 채 다시 읽는다")
  func sameVisitKeepsContentWhileReloading() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let visit = UUID()
    let first = openDetail(model, trip: TripFixture.jeju, visit: visit)
    await waitUntil { model.content.detail != nil }
    let loaded = model.content
    await cancelAndWait(first)

    let second = openDetail(model, trip: TripFixture.jeju, visit: visit)
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == loaded)
    #expect(model.placeName == .named("제주특별자치도 제주시"))

    gates.open(1)
    await cancelAndWait(second)
  }

  @Test("판정이 바뀌어 사진이 더해지면 사진이 가장 많이 겹치는 여행을 같은 여행으로 다시 찾아 갱신한다")
  func rejudgedTripIsFoundAgain() async throws {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju, TripFixture.tokyo],
      places: TripFixture.jejuPlace
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail?.photos.count == 4 }

    try await photoStore.save([TripFixture.extraJejuPhoto])
    try await photoStore.replaceTrips([TripFixture.jejuWithExtraPhoto, TripFixture.tokyo])
    model.libraryStoreChanged()
    await waitUntil { model.content.detail?.photos.count == 5 }
    #expect(model.content.detail?.trip == TripFixture.jejuWithExtraPhoto)

    await cancelAndWait(appear)
  }

  @Test("사진이 겹치는 여행이 없으면 찾을 수 없음이고 이름을 묻지 않으며, 여행이 돌아오면 다시 찾는다")
  func notFoundThenFoundAgain() async throws {
    let map = MapClientFake()
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.tokyo]
    )
    let model = TripFixture.detailModel(photoStore: photoStore, map: map)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content == .notFound }
    await settle()
    #expect(map.placeNameRequests.isEmpty)

    try await photoStore.replaceTrips([TripFixture.jeju, TripFixture.tokyo])
    model.libraryStoreChanged()
    await waitUntil { model.content.detail?.trip == TripFixture.jeju }

    await cancelAndWait(appear)
  }

  @Test("다른 여행을 열면 지난 여행의 내용과 이름 대신 불러오는 중부터 보인다")
  func otherTripStartsLoading() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju, TripFixture.tokyo],
      places: TripFixture.jejuPlace,
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail != nil }
    await cancelAndWait(first)

    let second = openDetail(model, trip: TripFixture.tokyo, visit: UUID())
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == .loading)
    #expect(model.placeName == .loading)

    gates.open(1)
    await waitUntil { model.content.detail?.trip == TripFixture.tokyo }
    await cancelAndWait(second)
  }
}
