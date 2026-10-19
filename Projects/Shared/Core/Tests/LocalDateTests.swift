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
}
