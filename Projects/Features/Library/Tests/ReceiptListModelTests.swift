import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 영수증 목록 읽기·다시 읽기와 달력. 읽기를 붙잡을 때는 `onReceipts` 에 `CallGates` 를, 실패는 `receiptsErrors` 를 쓴다.
@MainActor
struct ReceiptListModelTests {
  @Test("열면 읽는 동안 불러오는 중이고, 읽으면 영수증만 최신순으로 담는다")
  func showsLoadingThenItems() async {
    let gates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [
        .receipt(id: "old", creationDate: .seoul(2026, 9, 1, hour: 12), info: ReceiptFixture.info("가게", won: 9000)),
        .receipt(id: "new", creationDate: .seoul(2026, 10, 1, hour: 12), info: nil),
        .dated(id: "food", .seoul(2026, 10, 2, hour: 12), categories: [.food]),
      ],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)

    let appear = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.content == .loading)

    gates.open(0)
    await waitUntil { model.content != .loading }
    #expect(model.content.ids == ["new", "old"])
    #expect(model.content.items?.map(\.status) == [.checking, .extracted(ReceiptFixture.info("가게", won: 9000))])

    await cancelAndWait(appear)
  }

  @Test("영수증이 없으면 빈 목록이다")
  func emptyShowsEmpty() async {
    let model = ReceiptFixture.listModel(photoStore: PhotoStoreClientFake(images: [.dated(id: "a", nil)]))

    let appear = Task { await model.onAppear() }
    await waitUntil { model.content != .loading }
    #expect(model.content == .loaded([]))

    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 실패다")
  func missingStoreShowsFailed() async {
    let model = ReceiptFixture.listModel(photoStore: nil)

    await model.onAppear()

    #expect(model.content == .failed)
  }

  @Test("처음 읽지 못하면 실패이고, 다시 시도하면 불러오는 중을 거쳐 목록이 보인다")
  func retryAfterFailureReloads() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.receipt(id: "a", info: nil)],
      receiptsErrors: [0: .failed],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    #expect(model.content == .loading)
    await waitUntil { gates.hasEntered(1) }

    gates.open(1)
    await waitUntil { model.content.ids == ["a"] }

    await cancelAndWait(appear)
  }

  @Test("실패가 아니면 다시 시도는 아무것도 하지 않는다")
  func retryIgnoredUnlessFailed() async {
    let photoStore = PhotoStoreClientFake(images: [.receipt(id: "a", info: nil)])
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["a"] }

    model.retryButtonTapped()
    await settle()

    #expect(model.content.ids == ["a"])
    #expect(photoStore.receiptsCallCount == 1)

    await cancelAndWait(appear)
  }

  @Test("다시 읽기에 실패하면 지난 목록을 둔다")
  func reloadFailureKeepsItems() async {
    // 실패한 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째를 붙잡아 실패 처리 뒤의 상태를 본다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(
      images: [.receipt(id: "a", info: nil)],
      receiptsErrors: [1: .failed],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["a"] }

    model.libraryStoreChanged()
    await settle()
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.content.ids == ["a"])

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("저장소 변경 신호로 다시 읽어 소급 추출한 가게·금액이 보인다")
  func storeChangeReloads() async throws {
    let photoStore = PhotoStoreClientFake(images: [.receipt(id: "a", info: nil)])
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content.items?.first?.status == .checking }

    let info = ReceiptFixture.info("예시분식", won: 8000)
    try await photoStore.saveReceipts(["a": info])
    model.libraryStoreChanged()
    await waitUntil { model.content.items?.first?.status == .extracted(info) }

    await cancelAndWait(appear)
  }

  @Test("읽는 도중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다")
  func coalescesSignalsDuringReload() async {
    let gates = CallGates(holding: [0, 1])
    let photoStore = PhotoStoreClientFake(
      images: [.receipt(id: "a", info: nil)],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }

    model.libraryStoreChanged()
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    gates.open(0)
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    await waitUntil { model.content.ids == ["a"] }
    await settle()
    #expect(!gates.hasEntered(2))

    await cancelAndWait(appear)
  }

  @Test("닫힌 뒤 늦게 끝난 읽기는 내용을 바꾸지 않고, 닫혀 있는 동안 신호는 버린다")
  func lateResultAfterCloseIsDropped() async throws {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.receipt(id: "a", info: nil)],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["a"] }

    // 다시 읽기가 결과를 계산한 뒤 붙잡힌 채 화면이 닫히고, 그사이 저장소가 바뀐다.
    try await photoStore.save([.receipt(id: "b", info: nil)])
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    first.cancel()
    gates.open(1)
    await first.value
    #expect(model.content.ids == ["a"])

    model.libraryStoreChanged()
    await settle()
    #expect(!gates.hasEntered(2))
  }

  @Test("화면을 닫았다 바로 열면 지난 Task 의 늦은 결과는 버리고 새 진입이 읽은 목록을 둔다")
  func staleTaskAfterReopenIsDropped() async throws {
    // 지난 읽기는 취소해도 풀리지 않는다(저장소 호출은 취소되지 않는다).
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [.receipt(id: "a", info: nil)],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }
    first.cancel()

    try await photoStore.save([.receipt(id: "b", info: nil)])
    let second = Task { await model.onAppear() }
    await waitUntil { model.content.ids?.count == 2 }

    gates.open(0)
    await first.value
    #expect(model.content.ids?.count == 2)

    await cancelAndWait(second)
  }

  @Test("다시 열면(상세에서 돌아오면) 지난 목록을 둔 채 한 번 다시 읽는다")
  func reopenKeepsItemsWhileReloading() async throws {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.receipt(id: "a", info: nil)],
      onReceipts: { await gates.pass($0) }
    )
    let model = ReceiptFixture.listModel(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { model.content.ids == ["a"] }
    // 상세를 열어 목록의 `.task` 가 끝난다. 그동안 저장소가 바뀐다.
    await cancelAndWait(first)
    try await photoStore.save([.receipt(id: "b", info: nil)])

    let second = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content.ids == ["a"])

    gates.open(1)
    await waitUntil { model.content.ids?.count == 2 }
    await settle()
    #expect(photoStore.receiptsCallCount == 2)

    await cancelAndWait(second)
  }

  @Test("달력은 읽을 때와 날짜·시간대가 바뀔 때 기기 달력으로 다시 담고, 닫혀 있어도 저장소를 읽지 않는다")
  func calendarFollowsClock() async {
    let clock = TestClock(now: GifticonFixture.now, calendar: .seoul)
    let photoStore = PhotoStoreClientFake()
    let model = ReceiptFixture.listModel(photoStore: photoStore, clock: clock)
    #expect(model.calendar.timeZone.identifier == "Asia/Seoul")

    clock.calendar = .newYork
    // 화면이 닫혀 있어도 담는다.
    model.dayChanged()
    #expect(model.calendar.timeZone.identifier == "America/New_York")
    #expect(photoStore.receiptsCallCount == 0)

    clock.calendar = .losAngeles
    let appear = Task { await model.onAppear() }
    await waitUntil {
      model.calendar.timeZone.identifier == "America/Los_Angeles" && model.content == .loaded([])
    }

    await cancelAndWait(appear)
  }
}
