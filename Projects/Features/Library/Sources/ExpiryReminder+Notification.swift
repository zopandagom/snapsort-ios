import Core
import Foundation
import NotificationInterface

/// 만료 알림의 식별자와 문구. Core 는 문구를 갖지 않으므로 화면 쪽에 둔다 (docs/ARCHITECTURE.md §4 만료 알림).
/// 문구에 교환처·OCR 텍스트·식별자는 넣지 않는다(잠금 화면에 보인다).
extension ExpiryReminder {
  /// 이 앱이 예약하는 만료 알림의 식별자 앞부분. 동기화는 이 앞부분인 대기 알림만 지우고 더한다.
  static let notificationIDPrefix = "expiry."

  /// 식별자가 달력 체계·날짜·개수(=문구)를 모두 담아, 식별자가 같으면 내용과 트리거 구성 요소도 같다. 그래서 동기화는 식별자 차이만 본다.
  /// 달력 체계를 담는 것은 Impl 이 예약 때의 기기 달력 era·연도로 트리거를 만들기 때문이다. 기기 달력을 바꾸면 식별자가 달라져
  /// 다음 동기화가 지우고 다시 넣는다. 시각·문구 규칙을 바꾸면 v 를 올려 이전 예약이 모두 바뀌게 한다.
  /// - Parameter calendar: Impl 이 트리거에 쓰는 것과 같은 기기 달력(App 은 `.autoupdatingCurrent`).
  func notificationRequest(calendar: Calendar) -> NotificationRequest {
    let day = String(format: "%04d%02d%02d", self.date.year, self.date.month, self.date.day)
    let id = [
      "\(Self.notificationIDPrefix)v1",
      String(describing: calendar.identifier),
      day,
      String(self.expiringTomorrowCount),
      String(self.expiringInWeekCount),
    ].joined(separator: ".")
    return NotificationRequest(
      id: id,
      title: "기프티콘 만료 알림",
      body: self.body,
      date: self.date,
      hour: ExpiryReminderPlanner.reminderHour,
      minute: ExpiryReminderPlanner.reminderMinute
    )
  }

  private var body: String {
    let tomorrow = self.expiringTomorrowCount
    let inWeek = self.expiringInWeekCount
    if tomorrow > 0, inWeek > 0 {
      return "기프티콘 \(tomorrow + inWeek)개가 곧 만료돼요 (내일 \(tomorrow)개, 7일 뒤 \(inWeek)개)"
    } else if tomorrow > 0 {
      return "기프티콘 \(tomorrow)개가 내일 만료돼요"
    } else {
      return "기프티콘 \(inWeek)개가 7일 뒤 만료돼요"
    }
  }
}
