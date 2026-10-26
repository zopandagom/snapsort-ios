import Core
import Foundation
import Testing

struct CaptureInboxWindowTests {
  private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  @Test("시작은 오늘을 포함한 30일 중 첫날 0시다")
  func startIsMidnightTwentyNineDaysAgo() {
    let calendar = gregorianCalendar("Asia/Seoul")
    let now = Self.date(2026, 10, 24, 15, calendar: calendar)

    let start = CaptureInboxWindow.start(now: now, calendar: calendar)

    #expect(start == Self.date(2026, 9, 25, calendar: calendar))
  }

  @Test("29일 전 0시는 포함이고 그 1초 전(30일 전 날)은 시작보다 앞이다")
  func boundary() throws {
    let calendar = gregorianCalendar("Asia/Seoul")
    let now = Self.date(2026, 10, 24, 15, calendar: calendar)

    let start = try #require(CaptureInboxWindow.start(now: now, calendar: calendar))

    #expect(start <= Self.date(2026, 9, 25, calendar: calendar))
    #expect(Self.date(2026, 9, 24, 23, calendar: calendar) < start)
  }

  @Test("오늘 0시 정각에도 같은 시작이다")
  func atMidnight() {
    let calendar = gregorianCalendar("Asia/Seoul")

    let start = CaptureInboxWindow.start(now: Self.date(2026, 10, 24, calendar: calendar), calendar: calendar)

    #expect(start == Self.date(2026, 9, 25, calendar: calendar))
  }

  private static func ymd(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
    DateComponents(year: year, month: month, day: day)
  }

  struct TransitionCase: Sendable {
    let zone: String
    let now: DateComponents
    let expectedStart: DateComponents
  }

  @Test("시간대 전환일을 지나도 시작은 그날 0시다", arguments: [
    TransitionCase(zone: "America/New_York", now: Self.ymd(2026, 11, 3), expectedStart: Self.ymd(2026, 10, 5)),
    TransitionCase(zone: "Europe/Berlin", now: Self.ymd(2026, 10, 30), expectedStart: Self.ymd(2026, 10, 1)),
    TransitionCase(zone: "America/Sao_Paulo", now: Self.ymd(2018, 11, 20), expectedStart: Self.ymd(2018, 10, 22)),
  ])
  func acrossDaylightSavingTransition(_ testCase: TransitionCase) throws {
    let calendar = gregorianCalendar(testCase.zone)
    let now = try Self.date(
      #require(testCase.now.year),
      #require(testCase.now.month),
      #require(testCase.now.day),
      12,
      calendar: calendar
    )
    let expected = try Self.date(
      #require(testCase.expectedStart.year),
      #require(testCase.expectedStart.month),
      #require(testCase.expectedStart.day),
      12,
      calendar: calendar
    )

    let start = CaptureInboxWindow.start(now: now, calendar: calendar)

    #expect(start == calendar.startOfDay(for: expected))
  }

  @Test("0시가 없는 전환일(브라질 2018-11-04)이 시작이어도 그날 첫 시각이다")
  func startOnDayWithoutMidnight() throws {
    let calendar = gregorianCalendar("America/Sao_Paulo")
    let now = Self.date(2018, 12, 3, 12, calendar: calendar)

    let start = try #require(CaptureInboxWindow.start(now: now, calendar: calendar))

    #expect(calendar.component(.day, from: start) == 4)
    #expect(calendar.component(.month, from: start) == 11)
    #expect(start == calendar.startOfDay(for: start))
  }

  @Test("일본력이어도 같은 시각이다")
  func japaneseCalendarMatchesGregorian() {
    let gregorian = gregorianCalendar("Asia/Tokyo")
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = gregorian.timeZone
    let now = Self.date(2026, 10, 24, 9, calendar: gregorian)

    #expect(CaptureInboxWindow.start(now: now, calendar: japanese) == CaptureInboxWindow.start(
      now: now,
      calendar: gregorian
    ))
  }
}
