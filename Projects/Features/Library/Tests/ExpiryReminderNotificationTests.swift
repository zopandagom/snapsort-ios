import Core
import Foundation
import Testing
@testable import LibraryFeature

struct ExpiryReminderNotificationTests {
  @Test(
    "알림 식별자는 달력 체계·8자리 날짜·개수를 담고, 문구는 개수만 담는다",
    arguments: [
      (1, 0, "expiry.v1.gregorian.20270105.1.0", "기프티콘 1개가 내일 만료돼요"),
      (0, 3, "expiry.v1.gregorian.20270105.0.3", "기프티콘 3개가 7일 뒤 만료돼요"),
      (2, 1, "expiry.v1.gregorian.20270105.2.1", "기프티콘 3개가 곧 만료돼요 (내일 2개, 7일 뒤 1개)"),
    ]
  )
  func notificationRequestWording(tomorrow: Int, inWeek: Int, id: String, body: String) {
    let reminder = ExpiryReminder(date: .date(2027, 1, 5), expiringTomorrowCount: tomorrow, expiringInWeekCount: inWeek)

    let request = reminder.notificationRequest(calendar: .seoul)

    #expect(request.id == id)
    #expect(request.title == "기프티콘 만료 알림")
    #expect(request.body == body)
    #expect(request.date == .date(2027, 1, 5))
    #expect(request.hour == 9)
    #expect(request.minute == 0)
  }

  @Test("알림 식별자의 달력 부분은 넘긴 기기 달력 체계다")
  func notificationRequestCalendarName() {
    let reminder = ExpiryReminder(date: .date(2026, 12, 24), expiringTomorrowCount: 1, expiringInWeekCount: 0)

    let request = reminder.notificationRequest(calendar: Calendar(identifier: .japanese))

    #expect(request.id == "expiry.v1.japanese.20261224.1.0")
  }
}
