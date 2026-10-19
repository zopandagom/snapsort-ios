import Core
import Foundation
import Testing

struct ExpiryReminderPlannerTests {
  @Test("한 장이면 7일 전·1일 전 두 알림을 만든다")
  func plansTwoRemindersForOneGifticon() throws {
    let reminders = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 11, 20))],
      now: seoulTime(2026, 10, 19, hour: 12),
      calendar: seoulCalendar()
    )

    #expect(try reminders == [
      ExpiryReminder(date: day(2026, 11, 13), expiringTomorrowCount: 0, expiringInWeekCount: 1),
      ExpiryReminder(date: day(2026, 11, 19), expiringTomorrowCount: 1, expiringInWeekCount: 0),
    ])
  }

  @Test("울릴 날이 지난 알림은 뺀다. 오늘 만료면 알림이 없다")
  func dropsPastReminders() throws {
    let now = try seoulTime(2026, 10, 19, hour: 12)

    let inThreeDays = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 10, 22))],
      now: now,
      calendar: seoulCalendar()
    )
    let today = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 10, 19))],
      now: now,
      calendar: seoulCalendar()
    )

    #expect(try inThreeDays == [
      ExpiryReminder(date: day(2026, 10, 21), expiringTomorrowCount: 1, expiringInWeekCount: 0),
    ])
    #expect(today.isEmpty)
  }

  @Test("오늘 울릴 알림은 09:00 전에만 넣는다", arguments: [(8, 59, true), (9, 0, false), (9, 1, false)])
  func keepsTodayReminderOnlyBeforeNine(hour: Int, minute: Int, isKept: Bool) throws {
    let reminders = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 10, 20))],
      now: seoulTime(2026, 10, 19, hour: hour, minute: minute),
      calendar: seoulCalendar()
    )

    #expect(try reminders == (isKept
        ? [ExpiryReminder(date: day(2026, 10, 19), expiringTomorrowCount: 1, expiringInWeekCount: 0)]
        : []))
  }

  @Test("같은 날 울릴 알림은 하나로 묶는다")
  func groupsRemindersOnSameDay() throws {
    let now = try seoulTime(2026, 10, 19, hour: 12)

    let sameExpiry = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 11, 20)), expiry("b", day(2026, 11, 20))],
      now: now,
      calendar: seoulCalendar()
    )
    // 11/14 는 11/15 만료의 1일 전이고 11/21 만료의 7일 전이다.
    let mixed = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 11, 15)), expiry("b", day(2026, 11, 21))],
      now: now,
      calendar: seoulCalendar()
    )

    #expect(try sameExpiry == [
      ExpiryReminder(date: day(2026, 11, 13), expiringTomorrowCount: 0, expiringInWeekCount: 2),
      ExpiryReminder(date: day(2026, 11, 19), expiringTomorrowCount: 2, expiringInWeekCount: 0),
    ])
    #expect(try mixed == [
      ExpiryReminder(date: day(2026, 11, 8), expiringTomorrowCount: 0, expiringInWeekCount: 1),
      ExpiryReminder(date: day(2026, 11, 14), expiringTomorrowCount: 1, expiringInWeekCount: 1),
      ExpiryReminder(date: day(2026, 11, 20), expiringTomorrowCount: 1, expiringInWeekCount: 0),
    ])
  }

  @Test("같은 이미지가 여러 번 오면 마지막 값으로 한 번만 센다")
  func countsSameImageOnce() throws {
    let reminders = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(2026, 11, 1)), expiry("a", day(2026, 11, 20))],
      now: seoulTime(2026, 10, 19, hour: 12),
      calendar: seoulCalendar()
    )

    #expect(try reminders == [
      ExpiryReminder(date: day(2026, 11, 13), expiringTomorrowCount: 0, expiringInWeekCount: 1),
      ExpiryReminder(date: day(2026, 11, 19), expiringTomorrowCount: 1, expiringInWeekCount: 0),
    ])
  }

  @Test("알림 날이 상한보다 많으면 날짜 오름차순으로 가까운 날부터 상한까지만 둔다")
  func keepsNearestRemindersUpToLimit() throws {
    let start = try day(2027, 1, 1)
    // 만료일을 100일씩 떨어뜨려 알림 날이 겹치지 않게 한다(35장 → 70개).
    let expiries = (0 ..< 35).map { expiry("image-\($0)", start.addingDays($0 * 100)) }

    let reminders = try ExpiryReminderPlanner.reminders(
      for: expiries.reversed(),
      now: seoulTime(2026, 10, 19, hour: 12),
      calendar: seoulCalendar()
    )

    let allDates = expiries.flatMap { [$0.expiryDate.addingDays(-7), $0.expiryDate.addingDays(-1)] }
    #expect(reminders.count == ExpiryReminderPlanner.maximumCount)
    #expect(reminders.map(\.date) == Array(allDates.prefix(ExpiryReminderPlanner.maximumCount)))
  }

  @Test(
    "알림 날은 월말·윤년·연말 경계를 넘어 센다",
    arguments: [
      (20_260_301, [20_260_222, 20_260_228]),
      (20_280_301, [20_280_223, 20_280_229]),
      (20_270_103, [20_261_227, 20_270_102]),
    ]
  )
  func countsAcrossMonthAndYearBoundaries(expiryDate: Int, reminderDates: [Int]) throws {
    let reminders = try ExpiryReminderPlanner.reminders(
      for: [expiry("a", day(expiryDate))],
      now: seoulTime(2026, 1, 1, hour: 12),
      calendar: seoulCalendar()
    )

    #expect(try reminders.map(\.date) == reminderDates.map(day))
  }

  @Test("오늘과 지금 시각은 넘긴 달력의 시간대로 정한다")
  func usesCalendarTimeZone() throws {
    // 2026-10-20 00:30 UTC 는 서울에서 2026-10-20 09:30 이다.
    let now = Date(timeIntervalSince1970: 1_792_456_200)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let expiries = try [expiry("a", day(2026, 10, 21))]

    let inUTC = ExpiryReminderPlanner.reminders(for: expiries, now: now, calendar: utc)
    let inSeoul = try ExpiryReminderPlanner.reminders(for: expiries, now: now, calendar: seoulCalendar())

    // 1일 전 알림 날 10/20 의 09:00 이 UTC 로는 아직 오지 않았고, 서울로는 지났다.
    #expect(try inUTC == [ExpiryReminder(date: day(2026, 10, 20), expiringTomorrowCount: 1, expiringInWeekCount: 0)])
    #expect(inSeoul.isEmpty)
  }

  @Test("결과는 입력 순서와 관계없이 날짜 오름차순이다")
  func sortsByDate() throws {
    let reminders = try ExpiryReminderPlanner.reminders(
      for: [expiry("c", day(2027, 3, 1)), expiry("a", day(2026, 12, 1)), expiry("b", day(2027, 1, 15))],
      now: seoulTime(2026, 10, 19, hour: 12),
      calendar: seoulCalendar()
    )

    #expect(reminders.map(\.date) == reminders.map(\.date).sorted())
    #expect(reminders.count == 6)
  }

  // MARK: - changes

  @Test("권한이 없거나 추출 대기가 있으면 예약을 건드리지 않는다(nil)", arguments: [(false, false), (false, true), (true, true)])
  func leavesRemindersWithoutAuthorizationOrWithPendingExtraction(isAuthorized: Bool, hasPendingExtraction: Bool) {
    let changes = ExpiryReminderPlanner.changes(
      desiredIDs: ["expiry.new"],
      pendingIDs: ["expiry.old"],
      managedPrefix: "expiry.",
      isAuthorized: isAuthorized,
      hasPendingExtraction: hasPendingExtraction
    )

    #expect(changes == nil)
  }

  @Test("관리 앞부분 중 원하지 않는 대기 알림은 지우고, 대기에 없는 원하는 알림은 더한다. 다른 앞부분은 건드리지 않는다")
  func computesDifference() {
    let changes = ExpiryReminderPlanner.changes(
      desiredIDs: ["expiry.keep", "expiry.new"],
      pendingIDs: ["expiry.keep", "expiry.old", "other.reminder"],
      managedPrefix: "expiry.",
      isAuthorized: true,
      hasPendingExtraction: false
    )

    #expect(changes == ReminderChanges(removals: ["expiry.old"], additions: ["expiry.new"]))
  }

  @Test("원하는 알림이 없으면 관리 앞부분인 대기 알림을 모두 지운다")
  func removesAllManagedWhenNothingDesired() {
    let changes = ExpiryReminderPlanner.changes(
      desiredIDs: [],
      pendingIDs: ["expiry.a", "expiry.b", "other.reminder"],
      managedPrefix: "expiry.",
      isAuthorized: true,
      hasPendingExtraction: false
    )

    #expect(changes == ReminderChanges(removals: ["expiry.a", "expiry.b"], additions: []))
  }

  @Test("원하는 알림과 대기 알림이 같으면 바꿀 것이 없다")
  func hasNoChangesWhenSame() {
    let changes = ExpiryReminderPlanner.changes(
      desiredIDs: ["expiry.a"],
      pendingIDs: ["expiry.a"],
      managedPrefix: "expiry.",
      isAuthorized: true,
      hasPendingExtraction: false
    )

    #expect(changes == ReminderChanges(removals: [], additions: []))
  }
}

private func day(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
  try #require(LocalDate(year: year, month: month, day: day))
}

/// yyyymmdd 정수로 적은 날짜.
private func day(_ dayNumber: Int) throws -> LocalDate {
  try day(dayNumber / 10000, dayNumber / 100 % 100, dayNumber % 100)
}

private func expiry(_ id: String, _ date: LocalDate) -> GifticonExpiry {
  GifticonExpiry(imageID: id, expiryDate: date)
}

private func seoulCalendar() throws -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
  return calendar
}

private func seoulTime(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) throws -> Date {
  try #require(seoulCalendar().date(from: DateComponents(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute
  )))
}
