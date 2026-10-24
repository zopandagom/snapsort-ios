import Core
import Foundation
import Observation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 검색 Model 의 닫기·상세 다녀오기·날짜 변경. 읽기를 붙잡을 때는 `onSearchEntries` 에 `CallGates` 를 쓴다.
@MainActor
struct SearchModelLifecycleTests {
  // MARK: - 닫기

  @Test("검색을 닫으면 색인과 결과를 놓고, 다시 열면 처음부터 읽는다")
  func dismissReleasesAndReopenReads() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks, .unreadText(id: "waiting")])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.results != nil }

    model.queryChanged("")
    model.searchDismissed()
    await cancelAndWait(first)
    #expect(model.results == nil)
    #expect(model.pendingTextCount == 0)
    #expect(model.loadState == .loading)
    // 닫은 뒤 신호는 읽지 않는다.
    model.libraryStoreChanged()
    await settle()
    #expect(photoStore.searchEntriesCallCount == 1)

    let second = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    #expect(photoStore.searchEntriesCallCount == 2)
    #expect(model.pendingTextCount == 1)

    await cancelAndWait(second)
  }

  @Test("닫은 뒤 늦게 끝난 읽기는 상태를 바꾸지 않는다")
  func lateReadAfterDismissIsDropped() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [SearchFixture.starbucks],
      onSearchEntries: { await gates.pass($0) }
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }

    model.searchDismissed()
    appear.cancel()
    gates.open(0)
    await appear.value
    #expect(model.loadState == .loading)
    #expect(model.pendingTextCount == 0)
  }

  @Test("색인을 만드는 도중 닫히거나 화면이 사라져도 늦은 색인은 버린다")
  func lateBuildAfterDismissOrCancelIsDropped() async {
    let buildGates = CallGates(holding: [0, 1], ignoresCancellation: true)
    defer {
      buildGates.open(0)
      buildGates.open(1)
    }
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, _) = SearchFixture.model(photoStore: photoStore, buildGates: buildGates)

    let first = Task { await model.onAppear() }
    await waitUntil { buildGates.hasEntered(0) }
    model.searchDismissed()
    first.cancel()
    buildGates.open(0)
    await first.value
    #expect(model.loadState == .loading)

    // 상세로 가며 `.task` 만 취소된 경우에는 지난 값을 바꾸지 않는다.
    let second = Task { await model.onAppear() }
    await waitUntil { buildGates.hasEntered(1) }
    second.cancel()
    buildGates.open(1)
    await second.value
    #expect(model.loadState == .loading)
  }

  // MARK: - 상세 다녀오기

  @Test("상세에 갔다 오면 지난 결과를 둔 채 한 번 다시 읽고 불러오는 중으로 돌아가지 않는다")
  func detailRoundTripKeepsResults() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs == ["starbucks"] }

    await cancelAndWait(first)
    #expect(model.loadState == .loaded)
    #expect(model.resultImageIDs == ["starbucks"])

    let second = Task { await model.onAppear() }
    await waitUntil { photoStore.searchEntriesCallCount == 2 }
    #expect(model.loadState == .loaded)
    #expect(model.resultImageIDs == ["starbucks"])

    await cancelAndWait(second)
  }

  @Test("입력 직후 대기 중에 상세로 갔다 오면 지난 색인으로 바로 거른다. 그 뒤 다시 읽기가 실패해도 결과가 검색어와 맞는다")
  func pendingQueryIsMatchedOnReturn() async {
    let waitGates = CallGates(holding: [1])
    defer { waitGates.open(1) }
    let photoStore = PhotoStoreClientFake(
      images: [SearchFixture.starbucks, SearchFixture.coupangCapture],
      searchEntriesErrors: [1: .failed]
    )
    let (model, probe) = SearchFixture.model(photoStore: photoStore, waitGates: waitGates)
    let first = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs == ["starbucks"] }

    // 두 번째 입력의 대기를 붙잡은 채 화면이 사라진다.
    model.queryChanged("쿠팡")
    await waitUntil { waitGates.hasEntered(1) }
    await cancelAndWait(first)
    #expect(model.resultImageIDs == ["starbucks"])
    #expect(!probe.matches.contains("쿠팡"))

    let second = Task { await model.onAppear() }
    await waitUntil { model.results?.query == "쿠팡" }
    #expect(model.resultImageIDs == ["coupang"])
    // 다시 읽기는 실패했고, 지난 색인으로 거른 결과가 남는다.
    await waitUntil { photoStore.searchEntriesCallCount == 2 }
    await settle()
    #expect(model.loadState == .loaded)
    #expect(model.results?.query == "쿠팡")

    await cancelAndWait(second)
  }

  // MARK: - 날짜 변경

  @Test("날짜·시간대가 바뀌면 달력을 다시 담고, 열려 있으면 다시 읽어 여행 줄 기간을 새 달력으로 계산한다. 닫혀 있으면 읽지 않는다")
  func dayChangedRecomputesTripPeriod() async {
    // 시간대를 모르는 제주 여행은 경도 추정(+8)이 서울 기기와 1시간 차라 기기 시간대로, 로스앤젤레스 기기와는 멀어 +8 고정으로 계산한다.
    let clock = TestClock(now: .seoul(2026, 10, 21, hour: 9), calendar: .seoul)
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: [TripFixture.jejuKey: CachedPlace(name: .named("제주특별자치도 제주시"), timeZoneIdentifier: nil)]
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore, clock: clock)
    #expect(model.calendar.timeZone.identifier == "Asia/Seoul")

    clock.calendar = .losAngeles
    // 닫혀 있어도 달력은 다시 담지만 저장소는 읽지 않는다.
    model.dayChanged()
    #expect(model.calendar.timeZone.identifier == "America/Los_Angeles")
    await settle()
    #expect(photoStore.searchEntriesCallCount == 0)

    clock.calendar = .seoul
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("제주")
    await waitUntil { model.results?.trips.first?.period.timeZone.identifier == "Asia/Seoul" }
    let callCount = photoStore.searchEntriesCallCount

    clock.calendar = .losAngeles
    model.dayChanged()
    await waitUntil { photoStore.searchEntriesCallCount == callCount + 1 }
    await waitUntil { model.results?.trips.first?.period.timeZone.secondsFromGMT() == 8 * 3600 }
    #expect(model.calendar.timeZone.identifier == "America/Los_Angeles")

    await cancelAndWait(appear)
  }

  @Test("달력이 같으면 달력을 다시 대입하지 않는다")
  func sameCalendarIsNotReassigned() {
    let (model, _) = SearchFixture.model(photoStore: PhotoStoreClientFake())
    let changes = CallCounter()
    withObservationTracking {
      _ = model.calendar
    } onChange: {
      _ = changes.next()
    }
    model.dayChanged()
    #expect(changes.next() == 0)
  }
}
