import Core
import Foundation
import IndexingInterface
import IndexingTesting
import NotificationInterface
import NotificationTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
import WidgetTimelineTesting
@testable import LibraryFeature

/// 만료 알림 동기화가 위젯에 보일 값이 바뀔 때만 위젯 갱신을 요청하는지. 지금 시각은 `ReminderFixture` 와 같다(2026-10-19 08:00).
/// 동기화 루프는 화면이 사라질 때까지 이어지므로, 결과를 확인한 뒤 Task 를 취소해 끝낸다.
@MainActor
struct LibraryModelWidgetTests {
  @Test("첫 동기화가 한 번 요청하고, 같은 값의 진행률이 반복되면 더 요청하지 않는다")
  func requestsOnceForSameSummaries() async {
    let gates = CallGates(holding: [2])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let widget = WidgetTimelineClientFake()
    let model = ReminderFixture.model(
      photoStore: Self.photoStore(),
      notification: NotificationClientFake(authorization: .authorized, onAuthorizationStatus: { await gates.pass($0) }),
      indexing: indexing,
      widgetTimeline: widget
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { widget.reloadCount == 1 }

    // 진행률로 같은 값의 동기화(1번)를 돌리고, 그것이 끝나 다음 동기화(2번)가 시작될 때까지 기다린다.
    await ReminderFixture.waitForPreviousSyncs(indexing: indexing, gates: gates, nextIndex: 1)
    await ReminderFixture.waitForPreviousSyncs(indexing: indexing, gates: gates, nextIndex: 2)

    #expect(widget.reloadCount == 1)

    appear.cancel()
    await appear.value
  }

  @Test("사용함 표시로 값이 바뀌면 한 번 더 요청한다")
  func requestsAgainAfterUsageChange() async {
    let photoStore = Self.photoStore()
    let widget = WidgetTimelineClientFake()
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(authorization: .authorized),
      widgetTimeline: widget
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { widget.reloadCount == 1 }

    _ = try? await photoStore.setGifticonUsed(true, id: "a")
    model.gifticonUsageChanged()
    await waitUntil { widget.reloadCount == 2 }

    appear.cancel()
    await appear.value
  }

  @Test("추출 대기가 생기면(확인 중) 한 번 더 요청한다")
  func requestsAgainWhenExtractionPending() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoStore = Self.photoStore()
    let widget = WidgetTimelineClientFake()
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(authorization: .authorized),
      indexing: indexing,
      widgetTimeline: widget
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { widget.reloadCount == 1 && indexing.activeRunCount == 1 }

    try? await photoStore.save([.extractionPendingGifticon(id: "b")])
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
    await waitUntil { widget.reloadCount == 2 }

    appear.cancel()
    await appear.value
  }

  @Test("추출 대기가 사라지면(확인 중 끝) 한 번 더 요청한다")
  func requestsAgainWhenExtractionFinishes() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoStore = PhotoStoreClientFake(images: [
      .extractedGifticon(id: "a", expiryDate: .date(2026, 10, 22)),
      .extractionPendingGifticon(id: "b"),
    ])
    let widget = WidgetTimelineClientFake()
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(authorization: .authorized),
      indexing: indexing,
      widgetTimeline: widget
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { widget.reloadCount == 1 && indexing.activeRunCount == 1 }

    // 만료일을 찾지 못한 추출 값이라 개수는 그대로이고 확인 중만 바뀐다.
    try? await photoStore.saveGifticons(["b": GifticonInfo(expiryDate: nil, redemptionPlace: nil)])
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
    await waitUntil { widget.reloadCount == 2 }

    appear.cancel()
    await appear.value
  }

  @Test("저장소를 읽지 못하면 요청하지 않는다")
  func noRequestWhenStoreFails() async {
    let gates = CallGates(holding: [1])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let widget = WidgetTimelineClientFake()
    let model = ReminderFixture.model(
      photoStore: PhotoStoreClientFake(
        images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 22))],
        gifticonError: .failed
      ),
      notification: NotificationClientFake(authorization: .authorized, onAuthorizationStatus: { await gates.pass($0) }),
      indexing: indexing,
      widgetTimeline: widget
    )
    let appear = Task { await model.onAppear() }

    await ReminderFixture.waitForPreviousSyncs(indexing: indexing, gates: gates, nextIndex: 1)

    #expect(widget.reloadCount == 0)

    appear.cancel()
    await appear.value
  }

  @Test("알림 권한이 없어도 요청한다", arguments: [NotificationAuthorization.denied, .notDetermined])
  func requestsWithoutNotificationPermission(_ authorization: NotificationAuthorization) async {
    let widget = WidgetTimelineClientFake()
    let model = ReminderFixture.model(
      photoStore: Self.photoStore(),
      notification: NotificationClientFake(authorization: authorization),
      widgetTimeline: widget
    )
    let appear = Task { await model.onAppear() }

    await waitUntil { widget.reloadCount == 1 }

    appear.cancel()
    await appear.value
  }

  @Test("날이 바뀌면(dayChanged) 한 번 더 요청한다")
  func requestsAgainWhenDayChanges() async {
    let clock = Mutex(Date.seoul(2026, 10, 19, hour: 8))
    let widget = WidgetTimelineClientFake()
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: nil,
      photoStore: Self.photoStore(),
      notification: NotificationClientFake(authorization: .authorized),
      widgetTimeline: widget,
      calendar: .seoul,
      now: { clock.withLock { $0 } }
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { widget.reloadCount == 1 }

    clock.withLock { $0 = .seoul(2026, 10, 20, hour: 0, minute: 1) }
    model.dayChanged()
    await waitUntil { widget.reloadCount == 2 }

    appear.cancel()
    await appear.value
  }

  /// 2026-10-22 만료 한 장(오늘 2026-10-19 기준 D-3).
  private static func photoStore() -> PhotoStoreClientFake {
    PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 22))])
  }
}

private extension IndexedImage {
  /// 글자를 읽었지만 아직 추출하지 않은 기프티콘(추출 대기).
  static func extractionPendingGifticon(id: String) -> IndexedImage {
    IndexedImage(asset: .stub(id: id), labels: [], textRecognition: .recognized([]), categories: [.gifticon])
  }
}
