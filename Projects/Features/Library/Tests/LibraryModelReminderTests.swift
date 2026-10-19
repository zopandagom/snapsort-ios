import Core
import Foundation
import IndexingInterface
import IndexingTesting
import NotificationInterface
import NotificationTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 만료 알림 동기화. 동기화 루프는 화면이 사라질 때까지 이어지므로, 결과를 확인한 뒤 Task 를 취소해 끝낸다.
/// 지금 시각과 달력은 `ReminderFixture.model` 이 고정한다.
@MainActor
struct LibraryModelReminderTests {
  @Test("권한이 있으면 화면 진입 때 만료 예정 기프티콘의 알림을 날짜마다 하나로 묶어 09:00 에 예약한다")
  func onAppearSchedulesReminders() async {
    // 10/23 만료의 7일 전(10/16)은 지났고, 10/22 에는 10/23 의 1일 전과 10/29 의 7일 전이 묶인다.
    let photoStore = PhotoStoreClientFake(images: [
      .extractedGifticon(id: "a", expiryDate: .date(2026, 10, 23)),
      .extractedGifticon(id: "b", expiryDate: .date(2026, 10, 29)),
      .extractedGifticon(id: "c", expiryDate: .date(2026, 11, 9)),
    ])
    let notification = NotificationClientFake(authorization: .authorized)
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }

    await waitUntil { notification.pendingRequests.count == 4 }
    #expect(notification.pendingRequests.map(\.id) == [
      "expiry.v1.gregorian.20261022.1.1",
      "expiry.v1.gregorian.20261028.1.0",
      "expiry.v1.gregorian.20261102.0.1",
      "expiry.v1.gregorian.20261108.1.0",
    ])
    #expect(notification.pendingRequests.map(\.body) == [
      "기프티콘 2개가 곧 만료돼요 (내일 1개, 7일 뒤 1개)",
      "기프티콘 1개가 내일 만료돼요",
      "기프티콘 1개가 7일 뒤 만료돼요",
      "기프티콘 1개가 내일 만료돼요",
    ])
    #expect(notification.pendingRequests.allSatisfy { $0.hour == 9 && $0.minute == 0 })
    #expect(model.notificationAuthorization == .authorized)
    #expect(model.hasPlannedReminder)

    appear.cancel()
    await appear.value
  }

  @Test("저장소를 읽지 못하면 기존 대기 알림을 지우지도 더하지도 않는다")
  func storeFailureKeepsReminders() async {
    let existing = ReminderFixture.request(id: "expiry.v1.gregorian.20261101.0.1")
    let notification = NotificationClientFake(authorization: .authorized, pending: [existing])
    let model = ReminderFixture.model(photoStore: PhotoStoreClientFake(error: .failed), notification: notification)
    let appear = Task { await model.onAppear() }

    await waitUntil { model.notificationAuthorization == .authorized }
    await settle()
    #expect(notification.removedBatches.isEmpty)
    #expect(notification.addAttemptCount == 0)
    #expect(notification.pendingRequests == [existing])

    appear.cancel()
    await appear.value
  }

  @Test("추출 대기 기프티콘이 있으면 기존 대기 알림을 지우지도 더하지도 않는다")
  func pendingExtractionKeepsReminders() async {
    let existing = ReminderFixture.request(id: "expiry.v1.gregorian.20261101.0.1")
    let photoStore = PhotoStoreClientFake(images: [
      .extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29)),
      // 기프티콘으로 분류해 글자를 읽었지만 지금 규칙으로 추출하지 않았다.
      IndexedImage(asset: .stub(id: "b"), labels: [], textRecognition: .recognized([]), categories: [.gifticon]),
    ])
    let notification = NotificationClientFake(authorization: .authorized, pending: [existing])
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }

    await waitUntil { model.hasPlannedReminder }
    await settle()
    #expect(notification.removedBatches.isEmpty)
    #expect(notification.addAttemptCount == 0)
    #expect(notification.pendingRequests == [existing])

    appear.cancel()
    await appear.value
  }

  @Test("원하지 않는 만료 알림은 지우고, 앞부분이 다른 대기 알림은 그대로 둔다")
  func removesStaleRemindersOnly() async {
    let stale = ReminderFixture.request(id: "expiry.v1.gregorian.20261101.0.1")
    let other = ReminderFixture.request(id: "other.1")
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let notification = NotificationClientFake(authorization: .authorized, pending: [stale, other])
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }

    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 + ["other.1"] }
    #expect(notification.removedBatches == [[stale.id]])

    appear.cancel()
    await appear.value
  }

  @Test("이미 예약된 알림은 다시 더하지 않는다")
  func doesNotReAddScheduled() async {
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let notification = NotificationClientFake(
      authorization: .authorized,
      pending: ReminderFixture.expectedIDsFor1029.map { ReminderFixture.request(id: $0) }
    )
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }

    await waitUntil { model.hasPlannedReminder }
    await settle()
    #expect(notification.addAttemptCount == 0)
    #expect(notification.removedBatches.isEmpty)

    appear.cancel()
    await appear.value
  }

  @Test("기기 달력 체계가 바뀌면 이전 달력의 알림을 지우고 지금 달력으로 다시 예약한다")
  func calendarChangeReschedules() async {
    let japanese = ["expiry.v1.japanese.20261022.0.1", "expiry.v1.japanese.20261028.1.0"]
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let notification = NotificationClientFake(
      authorization: .authorized,
      pending: japanese.map { ReminderFixture.request(id: $0) }
    )
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }

    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }
    #expect(notification.removedBatches == [Set(japanese)])

    appear.cancel()
    await appear.value
  }

  @Test("인덱싱 진행률을 받으면 다시 동기화해, 끝나기 전에 찾은 기프티콘의 알림도 예약한다")
  func progressTriggersSync() async {
    let photoStore = PhotoStoreClientFake()
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(authorization: .authorized)
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.notificationAuthorization == .authorized && indexing.activeRunCount == 1 }
    await settle()
    #expect(notification.pendingRequests.isEmpty)

    try? await photoStore.save([.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, pendingTextCount: 1))

    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }
    #expect(model.isIndexing)

    appear.cancel()
    await appear.value
  }

  @Test("인덱싱이 멈추면 다시 동기화한다")
  func stopTriggersSync() async {
    let photoStore = PhotoStoreClientFake()
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(authorization: .authorized)
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.notificationAuthorization == .authorized && indexing.activeRunCount == 1 }
    await settle()
    #expect(notification.pendingRequests.isEmpty)

    // 진행률 없이 저장소를 바꾸고 멈춘 것처럼 흉내 낸다.
    try? await photoStore.save([.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    indexing.finishRuns()

    await waitUntil { model.isIndexingStopped }
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    appear.cancel()
    await appear.value
  }

  @Test("일부 알림을 예약하지 못하면 나머지는 예약하고, 다음 동기화에서 빠진 것을 다시 시도한다")
  func partialAddFailureRetriesNextSync() async {
    let failingID = "expiry.v1.gregorian.20261028.1.0"
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(authorization: .authorized, failingAddIDs: [failingID])
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }

    await waitUntil { notification.addAttemptCount == 1 && indexing.activeRunCount == 1 }
    #expect(notification.pendingRequests.map(\.id) == ["expiry.v1.gregorian.20261022.0.1"])

    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { notification.addAttemptCount == 2 }
    #expect(notification.addedBatches.last == [])

    appear.cancel()
    await appear.value
  }
}
