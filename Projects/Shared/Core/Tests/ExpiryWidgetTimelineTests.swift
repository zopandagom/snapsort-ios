import Foundation
import Testing
@testable import Core

struct ExpiryWidgetTimelineTests {
  @Test("오늘부터 7일 뒤 만료까지 세고, 8일 뒤는 뺀다")
  func countsWithinWeekInclusive() throws {
    let summary = try todaySummary([
      expiry("a", day(2026, 10, 26)),
      expiry("b", day(2026, 11, 2)),
      expiry("c", day(2026, 11, 3)),
    ])

    #expect(summary.count == 2)
    #expect(summary.nearestDaysLeft == 0)
  }

  @Test("가장 가까운 만료일까지 남은 날을 센다. 오늘 만료는 D-day(0)")
  func nearestDaysLeft() throws {
    #expect(try todaySummary([expiry("a", day(2026, 10, 30)), expiry("b", day(2026, 10, 28))]).nearestDaysLeft == 2)
    #expect(try todaySummary([expiry("a", day(2026, 10, 26))]).nearestDaysLeft == 0)
  }

  @Test("어제 만료된 것은 오늘 요약에 없다")
  func dropsExpiredYesterday() throws {
    let summary = try todaySummary([expiry("a", day(2026, 10, 25))])

    #expect(try summary == ExpiryWidgetSummary(
      date: day(2026, 10, 26),
      count: 0,
      nearestDaysLeft: nil,
      isChecking: false
    ))
  }

  @Test("같은 imageID 는 한 번 센다(마지막 값)")
  func countsSameImageOnce() throws {
    let summary = try todaySummary([expiry("a", day(2026, 10, 27)), expiry("a", day(2026, 10, 29))])

    #expect(summary.count == 1)
    #expect(summary.nearestDaysLeft == 3)
  }

  @Test("0개면 가까운 날이 없다", arguments: [false, true])
  func emptyHasNoNearest(isChecking: Bool) throws {
    let summary = try #require(ExpiryWidgetTimeline.summaries(
      for: [],
      isChecking: isChecking,
      today: day(2026, 10, 26)
    ).first)

    #expect(try summary == ExpiryWidgetSummary(
      date: day(2026, 10, 26),
      count: 0,
      nearestDaysLeft: nil,
      isChecking: isChecking
    ))
  }

  @Test("확인 중 여부를 모든 날의 요약에 넣는다")
  func passesCheckingToEveryDay() throws {
    let summaries = try ExpiryWidgetTimeline.summaries(
      for: [expiry("a", day(2026, 10, 28))],
      isChecking: true,
      today: day(2026, 10, 26)
    )

    let allChecking = summaries.allSatisfy(\.isChecking)
    #expect(allChecking)
  }

  @Test("오늘~7일 뒤 8개 요약을 날짜 순서대로 만든다")
  func makesHorizonOfConsecutiveDays() throws {
    let today = try day(2026, 10, 26)

    let summaries = ExpiryWidgetTimeline.summaries(for: [], isChecking: false, today: today)

    #expect(summaries.count == ExpiryWidgetTimeline.horizonDays + 1)
    #expect(summaries.map(\.date) == (0 ... 7).map { today.addingDays($0) })
  }

  @Test("뒷날 요약은 그 사이 만료된 것을 빼고, 창에 새로 든 것을 센다")
  func laterDaysDropExpiredAndAddNew() throws {
    let summaries = try ExpiryWidgetTimeline.summaries(
      for: [expiry("a", day(2026, 10, 27)), expiry("b", day(2026, 11, 5))],
      isChecking: false,
      today: day(2026, 10, 26)
    )

    #expect(summaries.map(\.count) == [1, 1, 0, 1, 1, 1, 1, 1])
    #expect(summaries.map(\.nearestDaysLeft) == [1, 0, nil, 7, 6, 5, 4, 3])
  }

  @Test("월말·윤년 2월 말을 넘겨 센다")
  func crossesMonthEndAndLeapDay() throws {
    let summaries = try ExpiryWidgetTimeline.summaries(
      for: [expiry("a", day(2028, 3, 1))],
      isChecking: false,
      today: day(2028, 2, 25)
    )

    #expect(try summaries.map(\.date).prefix(6) == [
      day(2028, 2, 25), day(2028, 2, 26), day(2028, 2, 27), day(2028, 2, 28), day(2028, 2, 29), day(2028, 3, 1),
    ])
    #expect(summaries.first?.nearestDaysLeft == 5)
    #expect(summaries.map(\.count) == [1, 1, 1, 1, 1, 1, 0, 0])
  }

  @Test("그날 시작은 그 시간대의 00:00")
  func startOfDayIsMidnight() throws {
    let calendar = try zonedCalendar("Asia/Seoul")

    let start = try #require(ExpiryWidgetTimeline.startOfDay(day(2026, 10, 27), calendar: calendar))

    #expect(start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 0)))
  }

  @Test("자정이 없는 날(산티아고 2026-09-06, 00:00 → 01:00)은 그날 첫 시각")
  func startOfDayWithoutMidnightIsFirstMoment() throws {
    let calendar = try zonedCalendar("America/Santiago")

    let start = try #require(ExpiryWidgetTimeline.startOfDay(day(2026, 9, 6), calendar: calendar))

    #expect(try LocalDate(start, calendar: calendar) == day(2026, 9, 6))
    #expect(calendar.component(.hour, from: start) == 1)
    #expect(try LocalDate(start.addingTimeInterval(-1), calendar: calendar) == day(2026, 9, 5))
  }

  @Test("그레고리력이 아닌 기기 달력에서도 서기 날짜의 시작이다")
  func startOfDayUsesGregorianDate() throws {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))

    let start = try #require(ExpiryWidgetTimeline.startOfDay(day(2026, 10, 27), calendar: japanese))

    #expect(try LocalDate(start, calendar: japanese) == day(2026, 10, 27))
    #expect(japanese.component(.hour, from: start) == 0)
  }

  @Test("위젯 창은 만료 알림의 7일 전과 같은 상수")
  func windowMatchesWeekBeforeReminder() {
    #expect(ExpiryWidgetTimeline.windowDays == 7)
    #expect(ExpiryReminderPlanner.daysBefore.contains(ExpiryWidgetTimeline.windowDays))
  }
}

private func todaySummary(_ expiries: [GifticonExpiry]) throws -> ExpiryWidgetSummary {
  try #require(ExpiryWidgetTimeline.summaries(for: expiries, isChecking: false, today: day(2026, 10, 26)).first)
}

private func day(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
  try #require(LocalDate(year: year, month: month, day: day))
}

private func expiry(_ id: String, _ date: LocalDate) -> GifticonExpiry {
  GifticonExpiry(imageID: id, expiryDate: date)
}

private func zonedCalendar(_ identifier: String) throws -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: identifier))
  return calendar
}
