import Core
import Foundation
import MapInterface
import MapTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 상세의 다시 읽기 실패·늦은 결과·날짜 변경. 이름 요청이 끼지 않게 제주 여행에 캐시된 이름을 둔다.
@MainActor
struct TripDetailModelReloadTests {
  /// 다시 읽기에서 실패할 저장소 호출.
  enum FailingStep: CaseIterable {
    case trips
    case tripAssets
    case periodAssets
  }

  @Test("다시 읽기의 여행·사진·기간 캡처 읽기 중 하나가 실패하면 지난 내용을 둔다", arguments: FailingStep.allCases)
  func reloadFailureKeepsDetail(step: FailingStep) async {
    // 실패한 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째 여행 읽기를 붙잡아 실패 처리 뒤의 상태를 본다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      tripsErrors: step == .trips ? [1: .failed] : [:],
      onTrips: { await gates.pass($0) },
      tripAssetsErrors: step == .tripAssets ? [1: .failed] : [:],
      periodAssetsErrors: step == .periodAssets ? [1: .failed] : [:]
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail != nil }
    let loaded = model.content

    model.libraryStoreChanged()
    await settle()
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.content == loaded)

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("화면을 닫았다 바로 열면 지난 Task 가 늦게 읽은 사진은 버리고 새 진입이 읽은 내용을 둔다")
  func staleTripAssetsAfterReopenAreDropped() async throws {
    // 지난 읽기는 취소해도 풀리지 않는다(저장소 호출은 취소되지 않는다).
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      onTripAssets: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    first.cancel()

    try await photoStore.save([TripFixture.extraJejuPhoto])
    try await photoStore.replaceTrips([TripFixture.jejuWithExtraPhoto])
    let second = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail?.photos.count == 5 }

    gates.open(0)
    await first.value
    #expect(model.content.detail?.photos.count == 5)

    await cancelAndWait(second)
  }

  @Test("화면을 닫았다 바로 열면 지난 Task 가 늦게 읽은 기간 캡처는 버리고 새 진입이 읽은 내용을 둔다")
  func stalePeriodAssetsAfterReopenAreDropped() async throws {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: TripFixture.jejuPlace,
      onPeriodAssets: { await gates.pass($0) }
    )
    let model = TripFixture.detailModel(photoStore: photoStore)
    let first = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    first.cancel()

    try await photoStore.save([TripFixture.capture("receipt", .receipt, at: .seoul(2026, 7, 11, hour: 12))])
    let second = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail?.captureGroups.count == 1 }

    gates.open(0)
    await first.value
    #expect(model.content.detail?.captureGroups.count == 1)

    await cancelAndWait(second)
  }

  @Test("날짜·시간대가 바뀌면 달력을 다시 담고, 열려 있으면 다시 읽어 시간대를 모르는 여행의 기간을 다시 계산한다")
  func dayChangedRecomputes() async {
    // 시간대를 모르는 제주 여행은 경도 추정(+8)이 서울 기기와 1시간 차라 기기 시간대로, 로스앤젤레스 기기와는 멀어 +8 고정으로 계산한다.
    let clock = TestClock(now: .seoul(2026, 10, 21, hour: 9), calendar: .seoul)
    let photoStore = PhotoStoreClientFake(images: TripFixture.photos(of: TripFixture.jeju), trips: [TripFixture.jeju])
    let model = TripFixture.detailModel(photoStore: photoStore, clock: clock)
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { model.content.detail?.period.timeZone.identifier == "Asia/Seoul" }

    clock.calendar = .losAngeles
    model.dayChanged()
    #expect(model.calendar.timeZone.identifier == "America/Los_Angeles")
    await waitUntil { model.content.detail?.period.timeZone.secondsFromGMT() == 8 * 3600 }

    await cancelAndWait(appear)
  }
}
