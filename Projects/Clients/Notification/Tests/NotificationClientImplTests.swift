import Core
import Foundation
import NotificationInterface
import Testing
import UserNotifications
@testable import NotificationImpl

struct NotificationClientImplTests {
  @Test(
    "UNAuthorizationStatus 를 NotificationAuthorization 으로 변환한다",
    arguments: [
      (UNAuthorizationStatus.notDetermined, NotificationAuthorization.notDetermined),
      (.denied, .denied),
      (.authorized, .authorized),
      (.provisional, .authorized),
      (.ephemeral, .authorized),
    ]
  )
  func mapsAuthorizationStatus(status: UNAuthorizationStatus, expected: NotificationAuthorization) {
    #expect(NotificationClientImpl.authorization(status) == expected)
  }

  @Test("그레고리력 달력이면 서기 연도와 시각을 넣고 달력·시간대는 비워 둔다")
  func makesGregorianTriggerComponents() throws {
    let components = try #require(NotificationClientImpl.triggerDateComponents(
      for: Self.request(day(2026, 12, 24)),
      calendar: Self.calendar(.gregorian)
    ))

    #expect(components == DateComponents(era: 1, year: 2026, month: 12, day: 24, hour: 9, minute: 0))
    #expect(components.calendar == nil)
    #expect(components.timeZone == nil)
  }

  @Test(
    "기기 달력이 일본력·불교력이면 그 달력의 era·연도로 바꾼다",
    arguments: [(Calendar.Identifier.japanese, 236, 8), (.buddhist, 0, 2569)]
  )
  func convertsYearToDeviceCalendar(identifier: Calendar.Identifier, era: Int, year: Int) throws {
    let components = try #require(NotificationClientImpl.triggerDateComponents(
      for: Self.request(day(2026, 12, 24)),
      calendar: Self.calendar(identifier)
    ))

    #expect(components == DateComponents(era: era, year: year, month: 12, day: 24, hour: 9, minute: 0))
  }

  @Test("윤일도 그대로 넣는다")
  func keepsLeapDay() throws {
    let components = try #require(NotificationClientImpl.triggerDateComponents(
      for: Self.request(day(2028, 2, 29)),
      calendar: Self.calendar(.gregorian)
    ))

    #expect(components == DateComponents(era: 1, year: 2028, month: 2, day: 29, hour: 9, minute: 0))
  }

  @Test("요청을 식별자·제목·본문 그대로, 반복하지 않는 날짜 트리거로 바꾼다")
  func makesNotificationRequest() throws {
    let request = try Self.request(day(2026, 12, 24))

    let notificationRequest = try #require(NotificationClientImpl.request(request, calendar: Self.calendar(.gregorian)))

    #expect(notificationRequest.identifier == request.id)
    #expect(notificationRequest.content.title == request.title)
    #expect(notificationRequest.content.body == request.body)
    let trigger = try #require(notificationRequest.trigger as? UNCalendarNotificationTrigger)
    #expect(!trigger.repeats)
    #expect(trigger.dateComponents.year == 2026)
    #expect(trigger.dateComponents.hour == 9)
  }

  @Test("앱이 앞에 있을 때 배너·알림 목록·소리로 보인다")
  func presentsInForeground() {
    #expect(ForegroundPresenter.presentationOptions == [.banner, .list, .sound])
  }

  private static func request(_ date: LocalDate) -> NotificationRequest {
    NotificationRequest(id: "expiry.test", title: "제목", body: "본문", date: date, hour: 9, minute: 0)
  }

  private static func calendar(_ identifier: Calendar.Identifier) throws -> Calendar {
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    return calendar
  }
}

private func day(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
  try #require(LocalDate(year: year, month: month, day: day))
}
