import Core
import Foundation
import Testing

struct LocalDateTests {
  @Test("달력에 없는 날짜는 만들지 않는다")
  func rejectsInvalidDates() {
    #expect(LocalDate(year: 2026, month: 13, day: 1) == nil)
    #expect(LocalDate(year: 2026, month: 4, day: 31) == nil)
    #expect(LocalDate(year: 2026, month: 2, day: 29) == nil)
    #expect(LocalDate(year: 2100, month: 2, day: 29) == nil)
    #expect(LocalDate(year: 2000, month: 2, day: 29) != nil)
    #expect(LocalDate(year: 2028, month: 2, day: 29) != nil)
  }

  @Test("연·월·일 순서로 비교한다")
  func comparesByYearMonthDay() throws {
    let earlier = try #require(LocalDate(year: 2026, month: 12, day: 31))
    let later = try #require(LocalDate(year: 2027, month: 1, day: 1))
    #expect(earlier < later)
  }

  @Test("시각은 넘긴 달력의 시간대 기준 날짜가 된다")
  func usesCalendarTimeZone() throws {
    // 2026-12-31 15:30 UTC 는 서울에서 2027-01-01 00:30 이다.
    let date = Date(timeIntervalSince1970: 1_798_731_000)
    var seoul = Calendar(identifier: .gregorian)
    seoul.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))

    #expect(LocalDate(date, calendar: seoul) == LocalDate(year: 2027, month: 1, day: 1))
    #expect(LocalDate(date, calendar: utc) == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("일본력 달력을 넘겨도 서기 연도로 담는다")
  func usesGregorianYear() throws {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = try #require(TimeZone(identifier: "UTC"))
    let date = Date(timeIntervalSince1970: 1_798_731_000)
    #expect(LocalDate(date, calendar: japanese) == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("날짜 구성 요소에는 연·월·일만 채운다")
  func dateComponentsHaveDayOnly() throws {
    let components = try #require(LocalDate(year: 2026, month: 12, day: 31)).dateComponents
    #expect(components == DateComponents(year: 2026, month: 12, day: 31))
  }

  @Test(
    "며칠 뒤·앞 날짜는 월말·윤년·연말 경계를 넘어 센다",
    arguments: [
      (20_260_131, 1, 20_260_201),
      (20_280_228, 1, 20_280_229),
      (20_280_301, -1, 20_280_229),
      (20_260_301, -1, 20_260_228),
      (20_261_231, 1, 20_270_101),
      (20_270_103, -7, 20_261_227),
      (20_261_019, 0, 20_261_019),
      (20_261_019, -365, 20_251_019),
      (20_000_228, 1, 20_000_229),
      (21_000_228, 1, 21_000_301),
    ]
  )
  func addsDays(start: Int, days: Int, expected: Int) throws {
    let date = try #require(Self.date(start))
    #expect(date.addingDays(days) == Self.date(expected))
  }

  @Test(
    "두 날짜 사이 일수는 연말·윤년·400년 규칙을 넘어 세고, 앞이면 음수다",
    arguments: [
      (20_261_231, 20_270_101, 1),
      (20_270_101, 20_261_231, -1),
      (20_280_228, 20_280_301, 2),
      (20_270_228, 20_270_301, 1),
      (20_280_229, 20_280_229, 0),
      (21_000_228, 21_000_301, 1),
      (20_000_228, 20_000_301, 2),
      (20_261_019, 20_271_019, 365),
      (20_271_019, 20_281_019, 366),
    ]
  )
  func countsDaysUntil(start: Int, end: Int, expected: Int) throws {
    let startDate = try #require(Self.date(start))
    let endDate = try #require(Self.date(end))
    #expect(startDate.days(until: endDate) == expected)
    #expect(startDate.addingDays(expected) == endDate)
  }

  @Test("표시용 시각은 그 시간대의 그날 정오다", arguments: ["Asia/Seoul", "America/Los_Angeles", "UTC", "Pacific/Kiritimati"])
  func noonIsMiddayInTimeZone(identifier: String) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: identifier))
    let date = try #require(LocalDate(year: 2026, month: 12, day: 31))

    let noon = try #require(date.noon(in: calendar))

    #expect(LocalDate(noon, calendar: calendar) == date)
    #expect(calendar.component(.hour, from: noon) == 12)
  }

  @Test("자정이 없는 시간대 전환일에도 정오가 같은 날짜다")
  func noonOnDaylightSavingTransitionDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    let santiago = try #require(TimeZone(identifier: "America/Santiago"))
    calendar.timeZone = santiago
    // 칠레는 봄 전환 때 자정을 건너뛴다. 실제 전환일은 시간대 데이터에서 찾는다.
    let start = try Date("2026-08-01T00:00:00Z", strategy: .iso8601)
    let transition = try #require(santiago.nextDaylightSavingTimeTransition(after: start))
    let date = LocalDate(transition, calendar: calendar)

    let noon = try #require(date.noon(in: calendar))

    #expect(LocalDate(noon, calendar: calendar) == date)
    #expect(calendar.component(.hour, from: noon) == 12)
  }

  @Test("기기 달력이 일본력이어도 정오는 서기 날짜 그대로다")
  func noonWithJapaneseCalendar() throws {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let date = try #require(LocalDate(year: 2026, month: 12, day: 31))

    let noon = try #require(date.noon(in: japanese))

    #expect(LocalDate(noon, calendar: japanese) == date)
  }

  /// yyyymmdd 정수로 적은 날짜.
  private static func date(_ dayNumber: Int) -> LocalDate? {
    LocalDate(year: dayNumber / 10000, month: dayNumber / 100 % 100, day: dayNumber % 100)
  }
}
