/// 알림 권한 상태. UNAuthorizationStatus 를 Feature 에 노출하지 않기 위한 값 타입.
public enum NotificationAuthorization: Sendable, Equatable {
  case notDetermined
  case denied
  /// 허용. 임시 허용(provisional)·앱 클립 임시(ephemeral)도 예약할 수 있어 여기에 든다.
  case authorized
}
