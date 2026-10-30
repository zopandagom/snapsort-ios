import Core
import NotificationInterface

/// 만료 알림 버튼 표시와 대기 알림 맞추기. LibraryModel 파일 길이 때문에 나눴다.
public extension LibraryModel {
  /// "만료 알림 받기" 버튼을 보일지.
  var showsExpiryReminderButton: Bool {
    self.notificationAuthorization == .notDetermined && self.hasPlannedReminder
      && !self.isRequestingNotificationAuthorization
  }

  /// "설정에서 알림 켜기"를 보일지: 알림을 거부했고 지금 예약할 알림이 있다.
  var showsNotificationSettingsButton: Bool {
    self.notificationAuthorization == .denied && self.hasPlannedReminder
  }
}

extension LibraryModel {
  /// 원하는 알림과 대기 알림의 식별자 차이만 지우고 더한다(판단은 `ExpiryReminderPlanner.changes`, docs/ARCHITECTURE.md §4 만료 알림).
  /// 대기 알림을 읽은 뒤 `isCurrent` 가 거짓이면(지난 동기화 루프) 예약을 바꾸지 않는다.
  static func applyReminderChanges(
    _ desired: [NotificationRequest],
    status: NotificationAuthorization,
    hasPendingExtraction: Bool,
    notification: any NotificationClient,
    isCurrent: () -> Bool
  ) async {
    // `changes` 가 nil 을 낼 조건이면 알림 센터를 부르지 않는다.
    guard status == .authorized, !hasPendingExtraction, !Task.isCancelled else { return }
    let pendingIDs = await notification.pendingRequestIDs()
    guard isCurrent(), !Task.isCancelled,
          let changes = ExpiryReminderPlanner.changes(
            desiredIDs: Set(desired.map(\.id)),
            pendingIDs: pendingIDs,
            managedPrefix: ExpiryReminder.notificationIDPrefix,
            isAuthorized: status == .authorized,
            hasPendingExtraction: hasPendingExtraction
          )
    else { return }
    // 지우기와 더하기는 같은 시점의 계산이라 사이에 멈추지 않는다. 지우기를 먼저 해 대기 상한을 넘지 않게 한다.
    if !changes.removals.isEmpty {
      await notification.removePendingRequests(ids: changes.removals)
    }
    let additions = desired.filter { changes.additions.contains($0.id) }
    if !additions.isEmpty {
      // 실패한 것만 빠지고 나머지는 예약된다. 빠진 것은 다음 동기화가 다시 더한다.
      try? await notification.add(additions)
    }
  }
}
