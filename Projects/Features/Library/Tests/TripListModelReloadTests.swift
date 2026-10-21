import Core
import Foundation
import MapInterface
import MapTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 목록의 실패·다시 읽기·제한 접근·날짜 변경. 읽기를 붙잡을 때는 `onTrips` 에 `CallGates` 를, 실패는 `tripsErrors` 를 쓴다.
@MainActor
struct TripListModelReloadTests {
  @Test("처음 읽지 못하면 실패이고, 다시 시도하면 불러오는 중을 거쳐 목록이 보인다")
  func retryAfterFailureReloads() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      tripsErrors: [0: .failed],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    #expect(model.content == .loading)
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    await waitUntil { model.content.ids == ["jeju-0"] }

    await cancelAndWait(appear)
  }

  @Test("장소 캐시 읽기에 실패해도 처음 읽기는 실패다")
  func placesFailureFailsFirstRead() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      placeError: .failed
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content == .failed }
    await cancelAndWait(appear)
  }

  @Test("다시 읽기에 실패하면 지난 목록을 둔다")
  func reloadFailureKeepsItems() async {
    // 실패한 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째를 붙잡아 실패 처리 뒤의 상태를 본다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      tripsErrors: [1: .failed],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["jeju-0"] }

    model.libraryStoreChanged()
    await settle()
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.content.ids == ["jeju-0"])

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("저장소 변경 신호로 다시 읽어 바뀐 여행이 보이고, 읽는 도중 신호 여러 개는 한 번으로 합친다")
  func storeChangeReloadsAndCoalesces() async throws {
    let gates = CallGates(holding: [1, 2])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["jeju-0"] }

    try await photoStore.replaceTrips([TripFixture.jeju, TripFixture.tokyo])
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    gates.open(1)
    await waitUntil { gates.hasEntered(2) }
    gates.open(2)
    await waitUntil { model.content.ids == ["tokyo-0", "jeju-0"] }
    await settle()
    #expect(photoStore.tripsCallCount == 3)

    await cancelAndWait(appear)
  }

  @Test("닫힌 뒤 늦게 끝난 읽기는 내용을 바꾸지 않고, 닫혀 있는 동안 신호는 버린다")
  func lateResultAfterCloseIsDropped() async throws {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["jeju-0"] }

    // 다시 읽기가 여행을 읽은 뒤 붙잡힌 채 화면이 닫힌다.
    try await photoStore.replaceTrips([TripFixture.jeju, TripFixture.tokyo])
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    first.cancel()
    gates.open(1)
    await first.value
    #expect(model.content.ids == ["jeju-0"])

    model.libraryStoreChanged()
    model.dayChanged()
    await settle()
    #expect(photoStore.tripsCallCount == 2)
  }

  @Test("화면을 닫았다 바로 열면 지난 Task 의 늦은 결과는 버리고 새 진입이 읽은 목록을 둔다")
  func staleTaskAfterReopenIsDropped() async throws {
    // 지난 읽기는 취소해도 풀리지 않는다(저장소 호출은 취소되지 않는다).
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju],
      onTrips: { await gates.pass($0) }
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }
    first.cancel()

    try await photoStore.replaceTrips([TripFixture.jeju, TripFixture.tokyo])
    let second = Task { await model.onAppear() }
    await waitUntil { model.content.ids?.count == 2 }

    gates.open(0)
    await first.value
    #expect(model.content.ids?.count == 2)

    await cancelAndWait(second)
  }

  @Test("제한 접근인지 처음과 읽을 때마다 다시 읽는다")
  func isLimitedFollowsAccessState() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .limited)
    let photoStore = PhotoStoreClientFake(images: TripFixture.photos(of: TripFixture.jeju), trips: [TripFixture.jeju])
    let model = TripFixture.listModel(photoStore: photoStore, photoLibrary: photoLibrary)
    #expect(model.isLimited)

    let appear = Task { await model.onAppear() }
    await waitUntil { model.content != .loading }
    photoLibrary.sendReloadAll(imageAssets: [], accessState: .authorized)
    model.libraryStoreChanged()
    await waitUntil { !model.isLimited }

    await cancelAndWait(appear)
  }

  @Test("날짜·시간대가 바뀌면 달력을 다시 담고, 열려 있으면 다시 읽어 시간대를 모르는 여행의 기간을 다시 계산한다")
  func dayChangedRecomputes() async {
    // 시간대를 모르는 제주 여행은 경도 추정(+8)이 서울 기기와 1시간 차라 기기 시간대로, 로스앤젤레스 기기와는 멀어 +8 고정으로 계산한다.
    let clock = TestClock(now: .seoul(2026, 10, 21, hour: 9), calendar: .seoul)
    let photoStore = PhotoStoreClientFake(images: TripFixture.photos(of: TripFixture.jeju), trips: [TripFixture.jeju])
    let model = TripFixture.listModel(photoStore: photoStore, clock: clock)
    #expect(model.calendar.timeZone.identifier == "Asia/Seoul")

    clock.calendar = .losAngeles
    // 화면이 닫혀 있어도 달력은 다시 담는다.
    model.dayChanged()
    #expect(model.calendar.timeZone.identifier == "America/Los_Angeles")

    clock.calendar = .seoul
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content.items?.first?.period.timeZone.identifier == "Asia/Seoul" }
    let callCount = photoStore.tripsCallCount

    clock.calendar = .losAngeles
    model.dayChanged()
    await waitUntil { photoStore.tripsCallCount == callCount + 1 }
    await waitUntil { model.content.items?.first?.period.timeZone.secondsFromGMT() == 8 * 3600 }
    #expect(model.calendar.timeZone.identifier == "America/Los_Angeles")

    await cancelAndWait(appear)
  }
}
