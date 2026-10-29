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

/// 알림 권한과 "만료 알림 받기" 버튼. 동기화 루프는 화면이 사라질 때까지 이어지므로, 결과를 확인한 뒤 Task 를 취소해 끝낸다.
/// 지금 시각과 달력은 `ReminderFixture.model` 이 고정한다.
@MainActor
struct LibraryModelReminderButtonTests {
  @Test(
    "권한을 정하지 않았고 예약할 알림이 있을 때만 버튼을 보인다",
    arguments: [
      (NotificationAuthorization.notDetermined, true),
      (.denied, false),
      (.authorized, false),
    ]
  )
  func buttonVisibilityByAuthorization(authorization: NotificationAuthorization, shows: Bool) async {
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(authorization: authorization)
    )
    let appear = Task { await model.onAppear() }

    await waitUntil { model.notificationAuthorization == authorization && model.hasPlannedReminder }
    #expect(model.showsExpiryReminderButton == shows)

    appear.cancel()
    await appear.value
  }

  @Test("만료 예정 기프티콘이 없으면 권한을 정하지 않았어도 버튼을 숨긴다")
  func buttonHiddenWithoutUpcomingExpiry() async {
    let photoStore = PhotoStoreClientFake(images: [
      .extractedGifticon(id: "a", expiryDate: nil),
      .extractedGifticon(id: "b", expiryDate: .date(2026, 10, 1)),
    ])
    let gates = CallGates(holding: [1])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(
        authorization: .notDetermined,
        onAuthorizationStatus: { await gates.pass($0) }
      ),
      indexing: indexing
    )
    let appear = Task { await model.onAppear() }

    // 권한은 저장소를 읽기 전에 바뀌므로, 권한이 아니라 동기화 끝을 기다린다.
    await ReminderFixture.waitForPreviousSyncs(indexing: indexing, gates: gates, nextIndex: 1)
    #expect(!model.hasPlannedReminder)
    #expect(!model.showsExpiryReminderButton)

    appear.cancel()
    await appear.value
  }

  @Test("오늘·내일 만료처럼 울릴 알림이 하나도 안 나오는 기프티콘만 있으면 버튼을 숨긴다")
  func buttonHiddenWhenNoReminderRemains() async {
    // 오늘 09:00 이 지나 내일 만료의 1일 전 알림도 울릴 수 없다.
    let photoStore = PhotoStoreClientFake(images: [
      .extractedGifticon(id: "a", expiryDate: .date(2026, 10, 19)),
      .extractedGifticon(id: "b", expiryDate: .date(2026, 10, 20)),
    ])
    let gates = CallGates(holding: [1])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(
        authorization: .notDetermined,
        onAuthorizationStatus: { await gates.pass($0) }
      ),
      indexing: indexing,
      now: .seoul(2026, 10, 19, hour: 9, minute: 30)
    )
    let appear = Task { await model.onAppear() }

    await ReminderFixture.waitForPreviousSyncs(indexing: indexing, gates: gates, nextIndex: 1)
    #expect(!model.hasPlannedReminder)
    #expect(!model.showsExpiryReminderButton)

    appear.cancel()
    await appear.value
  }

  @Test("버튼을 눌러 허용하면 한 번 요청하고 버튼을 숨긴 뒤 알림을 예약한다")
  func tapAllowSchedules() async {
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let notification = NotificationClientFake(authorization: .notDetermined, authorizationAfterRequest: .authorized)
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.showsExpiryReminderButton }
    #expect(notification.pendingRequests.isEmpty)

    await model.notificationsTapped()

    #expect(notification.requestAuthorizationCount == 1)
    #expect(model.notificationAuthorization == .authorized)
    #expect(!model.showsExpiryReminderButton)
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    appear.cancel()
    await appear.value
  }

  @Test("버튼을 눌러 거부하면 버튼을 숨기고 예약하지 않는다")
  func tapDenyDoesNotSchedule() async {
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let gates = CallGates(holding: [2])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .denied,
      onAuthorizationStatus: { await gates.pass($0) }
    )
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.showsExpiryReminderButton }

    await model.notificationsTapped()
    // 화면 진입(0번)과 탭(1번) 뒤의 동기화가 시작되면 탭이 요청한 동기화는 끝났다.
    await ReminderFixture.waitForPreviousSyncs(indexing: indexing, gates: gates, nextIndex: 2)

    #expect(model.notificationAuthorization == .denied)
    #expect(!model.showsExpiryReminderButton)
    #expect(notification.addAttemptCount == 0)
    #expect(notification.pendingRequests.isEmpty)

    appear.cancel()
    await appear.value
  }

  @Test("권한을 이미 정했으면 버튼 이벤트가 와도 다시 요청하지 않는다", arguments: [
    NotificationAuthorization.authorized, .denied,
  ])
  func tapIgnoredWhenDecided(authorization: NotificationAuthorization) async {
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let notification = NotificationClientFake(authorization: authorization, authorizationAfterRequest: .notDetermined)
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.notificationAuthorization == authorization }

    await model.notificationsTapped()

    #expect(notification.requestAuthorizationCount == 0)
    #expect(model.notificationAuthorization == authorization)

    appear.cancel()
    await appear.value
  }

  @Test("권한 요청 전에 읽은 권한으로 늦게 끝난 동기화는 요청 결과를 덮지 않는다")
  func syncOverlappingRequestKeepsResult() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .authorized,
      onAuthorizationStatus: { await gates.pass($0) }
    )
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.showsExpiryReminderButton && indexing.activeRunCount == 1 }

    // 두 번째 동기화가 미정을 읽은 채 붙잡혀 있는 동안 허용한다.
    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { gates.hasEntered(1) }
    await model.notificationsTapped()
    #expect(model.notificationAuthorization == .authorized)
    gates.open(1)

    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }
    #expect(model.notificationAuthorization == .authorized)
    #expect(!model.showsExpiryReminderButton)

    appear.cancel()
    await appear.value
  }

  @Test("권한 팝업이 떠 있는 동안 시작한 동기화는 팝업 중에 읽은 권한으로 요청 결과를 덮지 않는다")
  func syncStartedDuringPopupKeepsResult() async {
    let statusGates = CallGates(holding: [1, 2])
    let requestGate = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let notification = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .authorized,
      onAuthorizationStatus: { await statusGates.pass($0) },
      onRequestAuthorization: { await requestGate.pass(0) }
    )
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.showsExpiryReminderButton && indexing.activeRunCount == 1 }

    let tap = Task { await model.notificationsTapped() }
    await waitUntil { requestGate.hasEntered(0) }
    #expect(model.isRequestingNotificationAuthorization)
    #expect(!model.showsExpiryReminderButton)
    // 팝업 중에 동기화 S 를 시작시켜, S 가 미정을 읽은 채 붙잡는다.
    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { statusGates.hasEntered(1) }

    requestGate.open(0)
    await tap.value
    #expect(model.notificationAuthorization == .authorized)
    // S 를 풀고, 탭이 넣은 다음 동기화가 권한을 읽는 데서 붙잡힐 때까지(= S 가 끝날 때까지) 기다린다.
    statusGates.open(1)
    await waitUntil { statusGates.hasEntered(2) }
    #expect(model.notificationAuthorization == .authorized)
    #expect(!model.showsExpiryReminderButton)

    statusGates.open(2)
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    appear.cancel()
    await appear.value
  }

  @Test("알림이나 저장소가 없으면 권한을 읽지 않고 버튼도 보이지 않는다", arguments: [true, false])
  func noSyncWithoutClients(hasNotification: Bool) async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let notification = NotificationClientFake(authorization: .notDetermined)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: nil,
      photoStore: hasNotification ? nil : PhotoStoreClientFake(images: [
        .extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29)),
      ]),
      notification: hasNotification ? notification : nil,
      widgetTimeline: nil,
      tripPlace: nil,
      calendar: .seoul,
      now: { .seoul(2026, 10, 19, hour: 8) }
    )
    photoLibrary.finishImageChanges()

    // 동기화 루프가 시작하지 않으므로 이미지 관찰이 끝나면 돌아온다.
    await model.onAppear()

    #expect(model.notificationAuthorization == nil)
    #expect(!model.showsExpiryReminderButton)
  }
}
