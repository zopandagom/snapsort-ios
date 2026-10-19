import Core
import Foundation
import IndexingInterface
import IndexingTesting
import NotificationInterface
import NotificationTesting
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 만료 알림 동기화 루프의 요청 합침·재진입·취소와 권한 요청의 겹침. 붙잡을 호출은 `CallGates` 로 고른다.
/// 동기화 루프는 화면이 사라질 때까지 이어지므로, 결과를 확인한 뒤 Task 를 취소해 끝낸다.
@MainActor
struct LibraryModelReminderSyncTests {
  @Test("동기화 도중 들어온 요청 여러 개는 겹치지 않고 끝난 뒤 한 번으로 합친다")
  func coalescesRequestsDuringSync() async {
    let gates = CallGates(holding: [0, 1])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(
      authorization: .authorized,
      onAuthorizationStatus: { await gates.pass($0) }
    )
    let photoStore = Self.photoStore()
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }
    // 화면 진입 동기화가 권한을 읽는 데서 붙잡힌다.
    await waitUntil { gates.hasEntered(0) && indexing.activeRunCount == 1 }

    // 진행률은 개수를 다시 읽은 직후 같은 작업에서 동기화를 요청한다. 진행률마다 새 카테고리를 저장해 두고
    // 그 개수가 보일 때까지 기다리면, 그 진행률의 요청이 들어간 뒤다(열고 나서 요청이 오면 합쳐지지 않아 아래 검사가 거짓으로 실패한다).
    for (indexedCount, category) in zip(1 ... 3, [ImageCategory.map, .food, .receipt]) {
      try? await photoStore.save([.stub(id: "\(category.rawValue)", categories: [category])])
      indexing.sendProgress(IndexingProgress(totalCount: 3, indexedCount: indexedCount, skippedCount: 0))
      await waitUntil { model.categoryCounts[category] == 1 }
    }
    // 붙잡힌 동기화가 있는 동안 다음 동기화는 시작하지 않는다.
    await settle()
    #expect(!gates.hasEntered(1))

    gates.open(0)
    await waitUntil { gates.hasEntered(1) }

    gates.open(1)
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }
    await settle()
    // 세 요청이 한 번으로 합쳐졌다. 합쳐진 동기화는 이미 예약된 것을 다시 더하지 않는다.
    #expect(!gates.hasEntered(2))
    #expect(notification.addAttemptCount == 1)

    appear.cancel()
    await appear.value
  }

  @Test("화면을 나갔다 바로 들어와 지난 동기화가 늦게 깨어나도 권한 상태와 예약을 바꾸지 않는다")
  func staleSyncAfterReappearChangesNothing() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let notification = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .authorized,
      onAuthorizationStatus: { await gates.pass($0) }
    )
    let model = ReminderFixture.model(photoStore: Self.photoStore(), notification: notification)
    let first = Task { await model.onAppear() }
    // 지난 동기화가 미정을 읽은 채 붙잡힌다. 취소해도 풀리지 않는다.
    await waitUntil { gates.hasEntered(0) }
    first.cancel()

    // 모델을 거치지 않고 허용한다(설정 앱에서 허용한 것과 같다).
    _ = await notification.requestAuthorization()
    let second = Task { await model.onAppear() }
    await waitUntil {
      notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029
        && model.notificationAuthorization == .authorized
    }
    let added = notification.addedBatches
    let removed = notification.removedBatches

    gates.open(0)
    // 지난 동기화는 지난 진입의 Task 안에서 돌므로, 그 Task 가 끝나면 지난 동기화도 끝났다.
    await first.value

    #expect(model.notificationAuthorization == .authorized)
    #expect(!model.showsExpiryReminderButton)
    #expect(model.hasPlannedReminder)
    #expect(notification.addedBatches == added)
    #expect(notification.removedBatches == removed)
    #expect(notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029)

    second.cancel()
    await second.value
  }

  @Test("동기화 도중 화면이 사라지면 대기 알림을 지우지도 더하지도 않는다")
  func cancelDuringSyncChangesNothing() async {
    let gates = CallGates(holding: [0])
    // 붙잡지 않고 대기 조회가 불렸는지만 기록한다.
    let pendingGates = CallGates(holding: [])
    let stale = ReminderFixture.request(id: "expiry.v1.gregorian.20261101.0.1")
    let notification = NotificationClientFake(
      authorization: .authorized,
      pending: [stale],
      onAuthorizationStatus: { await gates.pass($0) },
      onPendingRequestIDs: { await pendingGates.pass($0) }
    )
    let model = ReminderFixture.model(photoStore: Self.photoStore(), notification: notification)
    let appear = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }

    // 취소로 붙잡힌 호출이 풀리고, 동기화는 저장소를 읽은 뒤 취소를 보고 멈춘다.
    appear.cancel()
    await appear.value

    // 저장소를 읽은 뒤 취소를 보고 멈춰, 대기 조회도 부르지 않는다.
    #expect(!pendingGates.hasEntered(0))
    #expect(notification.removedBatches.isEmpty)
    #expect(notification.addAttemptCount == 0)
    #expect(notification.pendingRequests.map(\.id) == [stale.id])
  }

  @Test("지난 루프에 남은 동기화 요청은 새 루프가 시작된 뒤 처리하지 않는다")
  func staleLoopDropsQueuedRequest() async {
    let gates = CallGates(holding: [0])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(
      authorization: .authorized,
      onAuthorizationStatus: { await gates.pass($0) }
    )
    let photoStore = Self.photoStore()
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let first = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) && indexing.activeRunCount == 1 }

    // 진행률은 개수를 다시 읽은 직후 같은 작업에서 동기화를 요청한다. 두 번째 화면 진입이 요청 신호를 먼저 바꾸면 요청이
    // 새 루프로 가므로, 새 카테고리 개수가 보일 때까지(= 요청이 지난 루프의 스트림에 쌓일 때까지) 기다린 뒤 다시 들어온다.
    try? await photoStore.save([.stub(id: "map", categories: [.map])])
    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { model.categoryCounts[.map] == 1 }
    // 지난 루프를 취소하지 않고 다시 들어와, 번호 비교만으로 쌓인 요청을 버리는지 본다.
    let second = Task { await model.onAppear() }
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    gates.open(0)
    await settle()

    // 지난 동기화는 권한을 읽은 뒤 끝나고, 지난 루프는 쌓인 요청으로 동기화를 시작하지 않는다.
    #expect(!gates.hasEntered(2))
    #expect(notification.addAttemptCount == 1)

    first.cancel()
    second.cancel()
    await first.value
    await second.value
  }

  @Test("화면을 나갔다 바로 들어와 저장소를 읽던 지난 동기화가 늦게 깨어나도 예약할 알림 여부를 덮지 않는다")
  func staleSyncAfterStoreReadChangesNothing() async throws {
    let storeGates = CallGates(holding: [0], ignoresCancellation: true)
    defer { storeGates.open(0) }
    let photoStore = PhotoStoreClientFake(onUpcomingGifticonExpiries: { await storeGates.pass($0) })
    let notification = NotificationClientFake(authorization: .authorized)
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let first = Task { await model.onAppear() }
    // 지난 동기화가 빈 만료 예정을 읽은 채 붙잡힌다. 취소해도 풀리지 않는다.
    await waitUntil { storeGates.hasEntered(0) }
    first.cancel()

    try await photoStore.save([.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let second = Task { await model.onAppear() }
    await waitUntil {
      notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 && model.hasPlannedReminder
    }
    let added = notification.addedBatches
    let removed = notification.removedBatches

    storeGates.open(0)
    // 지난 동기화는 지난 진입의 Task 안에서 돌므로, 그 Task 가 끝나면 지난 동기화도 끝났다.
    await first.value

    #expect(model.hasPlannedReminder)
    #expect(notification.addedBatches == added)
    #expect(notification.removedBatches == removed)

    second.cancel()
    await second.value
  }

  @Test("겹쳐 돈 지난 동기화가 대기 조회 뒤 깨어나도 예약을 바꾸지 않는다")
  func staleSyncAfterPendingReadChangesNothing() async {
    let pendingGates = CallGates(holding: [0])
    let notification = NotificationClientFake(
      authorization: .authorized,
      onPendingRequestIDs: { await pendingGates.pass($0) }
    )
    let model = ReminderFixture.model(photoStore: Self.photoStore(), notification: notification)
    let first = Task { await model.onAppear() }
    // 지난 동기화가 빈 대기 목록을 읽은 채 붙잡힌다.
    await waitUntil { pendingGates.hasEntered(0) }

    // 취소 보호와 떼어 보려고 지난 진입을 취소하지 않고 다시 들어온다.
    let second = Task { await model.onAppear() }
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }
    let added = notification.addedBatches

    pendingGates.open(0)
    await settle()

    #expect(notification.addedBatches == added)
    #expect(notification.addAttemptCount == 1)
    #expect(notification.removedBatches.isEmpty)

    first.cancel()
    second.cancel()
    await first.value
    await second.value
  }

  @Test("대기 조회 중 화면이 사라지면 대기 알림을 지우지도 더하지도 않는다")
  func cancelDuringPendingReadChangesNothing() async {
    let pendingGates = CallGates(holding: [0], ignoresCancellation: true)
    defer { pendingGates.open(0) }
    let stale = ReminderFixture.request(id: "expiry.v1.gregorian.20261101.0.1")
    let notification = NotificationClientFake(
      authorization: .authorized,
      pending: [stale],
      onPendingRequestIDs: { await pendingGates.pass($0) }
    )
    let model = ReminderFixture.model(photoStore: Self.photoStore(), notification: notification)
    let appear = Task { await model.onAppear() }
    await waitUntil { pendingGates.hasEntered(0) }

    // 취소는 동기로 전파되므로, 연 뒤 깨어난 동기화는 취소를 본다. 새 루프가 없어 번호 비교는 통과한다.
    appear.cancel()
    pendingGates.open(0)
    await appear.value

    #expect(notification.removedBatches.isEmpty)
    #expect(notification.addAttemptCount == 0)
    #expect(notification.pendingRequests.map(\.id) == [stale.id])
  }

  @Test("권한 팝업이 떠 있는 동안 버튼 이벤트가 다시 와도 한 번만 요청한다")
  func secondTapDuringPopupIsIgnored() async {
    let requestGate = CallGates(holding: [0])
    // 두 번째 요청은 붙잡지 않는 번호로 넘겨, 다시 요청하는 회귀가 멈춤이 아니라 횟수 실패로 드러나게 한다.
    let requestCalls = CallCounter()
    let notification = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .authorized,
      onRequestAuthorization: { await requestGate.pass(requestCalls.next()) }
    )
    let model = ReminderFixture.model(photoStore: Self.photoStore(), notification: notification)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.showsExpiryReminderButton }

    let tap = Task { await model.notificationsTapped() }
    await waitUntil { requestGate.hasEntered(0) }
    await model.notificationsTapped()
    #expect(notification.requestAuthorizationCount == 1)
    #expect(model.isRequestingNotificationAuthorization)

    requestGate.open(0)
    await tap.value
    #expect(notification.requestAuthorizationCount == 1)
    #expect(model.notificationAuthorization == .authorized)
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    appear.cancel()
    await appear.value
  }

  @Test("화면을 떠난 뒤 허용하면 그때는 예약하지 않고 다음 화면 진입에서 예약한다")
  func tapAfterLeavingSchedulesOnNextAppear() async {
    let notification = NotificationClientFake(authorization: .notDetermined, authorizationAfterRequest: .authorized)
    let model = ReminderFixture.model(photoStore: Self.photoStore(), notification: notification)
    let first = Task { await model.onAppear() }
    await waitUntil { model.showsExpiryReminderButton }
    first.cancel()
    await first.value

    // 동기화 루프가 끝난 뒤라 요청은 바로 돌아온 이 시점에 버려졌다.
    await model.notificationsTapped()

    #expect(notification.requestAuthorizationCount == 1)
    #expect(model.notificationAuthorization == .authorized)
    // 동기화 루프가 없어 요청 신호는 버려진다.
    #expect(notification.addAttemptCount == 0)

    let second = Task { await model.onAppear() }
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    second.cancel()
    await second.value
  }

  private static func photoStore() -> PhotoStoreClientFake {
    PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
  }
}
