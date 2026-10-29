/// 만료 알림 버튼 표시. LibraryModel 파일 길이 때문에 나눴다.
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
