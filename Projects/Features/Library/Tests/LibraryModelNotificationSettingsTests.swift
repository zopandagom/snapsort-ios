import Core
import Foundation
import NotificationInterface
import NotificationTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 거부 뒤 "설정에서 알림 켜기", 앱 복귀·사용 여부 변경·날짜 변경 때의 동기화.
/// 동기화 루프는 화면이 사라질 때까지 이어지므로, 결과를 확인한 뒤 Task 를 취소해 끝낸다.
@MainActor
struct LibraryModelNotificationSettingsTests {
  @Test(
    "알림을 거부했고 예약할 알림이 있을 때만 설정 버튼을 보인다",
    arguments: [
      (NotificationAuthorization.denied, LocalDate.date(2026, 10, 29), true),
      (.denied, .date(2026, 10, 19), false),
      (.notDetermined, .date(2026, 10, 29), false),
      (.authorized, .date(2026, 10, 29), false),
    ]
  )
  func settingsButtonVisibility(authorization: NotificationAuthorization, expiry: LocalDate, shows: Bool) async {
    // 오늘(10-19) 만료는 알림이 하나도 나오지 않는다.
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: expiry)])
    let model = ReminderFixture.model(
      photoStore: photoStore,
      notification: NotificationClientFake(authorization: authorization)
    )
    let appear = Task { await model.onAppear() }

    await waitUntil {
      model.notificationAuthorization == authorization && model.hasPlannedReminder == (expiry.day == 29)
    }
    #expect(model.showsNotificationSettingsButton == shows)

    await cancelAndWait(appear)
  }

  @Test("거부했을 때만 설정 버튼이 알림 설정을 연다", arguments: [NotificationAuthorization.denied, .authorized])
  func settingsTappedOpensSettingsOnlyWhenDenied(authorization: NotificationAuthorization) async {
    let notification = NotificationClientFake(authorization: authorization)
    let model = ReminderFixture.model(
      photoStore: PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))]),
      notification: notification
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { model.notificationAuthorization == authorization }

    await model.notificationSettingsTapped()

    #expect(notification.openSettingsCount == (authorization == .denied ? 1 : 0))

    await cancelAndWait(appear)
  }

  @Test("설정에서 허용하고 앱으로 돌아오면 권한을 다시 읽어 예약하고 설정 버튼이 사라진다")
  func sceneBecameActiveResyncs() async {
    let notification = NotificationClientFake(authorization: .denied, authorizationAfterRequest: .authorized)
    let model = ReminderFixture.model(
      photoStore: PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))]),
      notification: notification
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { model.showsNotificationSettingsButton }
    #expect(notification.pendingRequests.isEmpty)

    // 모델을 거치지 않고 허용한다(설정 앱에서 허용한 것과 같다).
    _ = await notification.requestAuthorization()
    model.sceneBecameActive()

    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }
    #expect(model.notificationAuthorization == .authorized)
    #expect(!model.showsNotificationSettingsButton)

    await cancelAndWait(appear)
  }

  @Test("사용함으로 바꾸면 그 기프티콘의 알림을 지우고, 되돌리면 다시 예약한다")
  func usageChangeResyncs() async throws {
    let notification = NotificationClientFake(authorization: .authorized)
    let photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
    let model = ReminderFixture.model(photoStore: photoStore, notification: notification)
    let appear = Task { await model.onAppear() }
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    _ = try await photoStore.setGifticonUsed(true, id: "a")
    model.gifticonUsageChanged()
    await waitUntil { notification.pendingRequests.isEmpty && !model.hasPlannedReminder }

    _ = try await photoStore.setGifticonUsed(false, id: "a")
    model.gifticonUsageChanged()
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    await cancelAndWait(appear)
  }

  @Test("날짜가 바뀌면 지난 날 알림을 빼고 예약할 알림이 있는지 다시 계산한다")
  func dayChangeResyncs() async {
    let clock = TestClock(now: .seoul(2026, 10, 19, hour: 8), calendar: .seoul)
    let notification = NotificationClientFake(authorization: .authorized)
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: nil,
      photoStore: PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))]),
      notification: notification,
      widgetTimeline: nil,
      tripPlace: nil,
      backgroundIndexing: nil,
      calendar: .seoul,
      now: { clock.now }
    )
    model.sceneBecameActive()
    let appear = Task { await model.onAppear() }
    await waitUntil { notification.pendingRequests.map(\.id) == ReminderFixture.expectedIDsFor1029 }

    // 7일 전 알림(10-22 09:00)이 지났다.
    clock.now = .seoul(2026, 10, 23, hour: 8)
    model.dayChanged()
    await waitUntil { notification.pendingRequests.map(\.id) == ["expiry.v1.gregorian.20261028.1.0"] }
    #expect(model.hasPlannedReminder)

    // 만료일 당일에는 알림이 남지 않는다.
    clock.now = .seoul(2026, 10, 29, hour: 8)
    model.dayChanged()
    await waitUntil { notification.pendingRequests.isEmpty && !model.hasPlannedReminder }

    await cancelAndWait(appear)
  }
}
