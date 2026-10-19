import Foundation
import UserNotifications

/// 앱이 앞에 있을 때 이 앱의 알림을 배너·알림 목록·소리로 보이게 한다. delegate 가 없으면 시스템이 표시하지 않아,
/// 울린 알림이 대기에서 빠지고(지난 시각은 다시 예약하지 않는다) 그날 알림을 놓친다 (docs/ARCHITECTURE.md §4 만료 알림).
/// 이 앱의 알림은 모두 Notification Client 가 예약한 것이라(서버 푸시 없음) 식별자로 거르지 않는다.
/// 알림을 눌렀을 때의 처리(didReceive)는 구현하지 않는다(딥링크는 별도 작업).
final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
  /// `UNUserNotificationCenter.delegate` 는 weak 이라 프로세스 수명 동안 붙잡아 둔다.
  static let shared = ForegroundPresenter()
  /// 앞에 있을 때 쓰는 표시 옵션.
  static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler(Self.presentationOptions)
  }
}
