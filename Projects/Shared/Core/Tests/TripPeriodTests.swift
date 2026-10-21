import Core
import Foundation
import Testing

/// 서울 기기 달력 기준. 시각은 "yyyy-MM-dd HH:mm(:ss)" 를 그 장소의 시간대 식별자로 읽는다.
/// 대체 규칙 기대값은 설계 실험(서울 기기, 기기 쪽 여유 2시간·추정 쪽 3시간)으로 확인한 값이다.
struct TripPeriodTests {
  // MARK: 시간대를 아는 여행 (여유 0, 확정 정의)

  @Test("아는 시간대면 첫 사진 날 0시부터 마지막 사진 다음 날 0시 전까지다")
  func knownTimeZoneUsesExactDays() throws {
    let trip = try Self.trip("2026-07-10 09:00", "2026-07-12 18:00", in: Self.seoul, longitude: 126.53)

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: Self.zone(Self.seoul))

    #expect(period.isTimeZoneKnown)
    #expect(period.timeZone.identifier == Self.seoul)
    #expect(try period.captureInterval.start == Self.at("2026-07-10 00:00", Self.seoul))
    #expect(try period.captureInterval.end == Self.at("2026-07-13 00:00", Self.seoul))
    #expect(try period.firstDay == Self.day(2026, 7, 10))
    #expect(try period.lastDay == Self.day(2026, 7, 12))
    #expect(try !period.contains("2026-07-09 23:59", Self.seoul))
    #expect(try period.contains("2026-07-12 23:59:59", Self.seoul))
    #expect(try !period.contains("2026-07-13 00:00", Self.seoul))
  }

  @Test("첫 사진이 00:00:00 이든 23:59:59 이든 그날이 첫날이다", arguments: ["2026-07-10 00:00:00", "2026-07-10 23:59:59"])
  func firstPhotoAtDayEdges(first: String) throws {
    let trip = try Self.trip(first, "2026-07-12 18:00", in: Self.seoul, longitude: 126.53)

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: Self.zone(Self.seoul))

    #expect(try period.firstDay == Self.day(2026, 7, 10))
    #expect(try period.captureInterval.start == Self.at("2026-07-10 00:00", Self.seoul))
  }

  @Test("자정이 없는 날은 01:00 에 시작하고 그날 끝은 다음 날 00:00 이다 (`startOfDay + 1일` 이면 01:00)")
  func dayWithoutMidnight() throws {
    let havana = "America/Havana"
    let trip = try Self.trip("2026-03-08 10:00", "2026-03-08 18:00", in: havana, longitude: -82.38)

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: Self.zone(havana))

    #expect(try period.captureInterval.start == Self.at("2026-03-08 01:00", havana))
    #expect(try period.captureInterval.end == Self.at("2026-03-09 00:00", havana))
  }

  @Test("일광절약이 끝나는 날은 25시간이다")
  func twentyFiveHourDay() throws {
    let newYork = "America/New_York"
    let trip = try Self.trip("2026-11-01 10:00", "2026-11-01 18:00", in: newYork, longitude: -74.0)

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: Self.zone(newYork))

    #expect(period.captureInterval.duration == 25 * 3600)
    #expect(try period.captureInterval.end == Self.at("2026-11-02 00:00", newYork))
  }

  @Test("아는 시간대면 자정 근처 사진도 여행지 날짜다(뉴욕 마지막 00:30·파리 첫 00:40·사모아)")
  func knownTimeZoneNearMidnight() throws {
    let calendar = try Self.seoulCalendar()
    let newYork = try Self.trip("2026-07-10 10:00", "2026-07-15 00:30", in: "America/New_York", longitude: -74.0)
    let newYorkPeriod = try TripPeriod(trip: newYork, calendar: calendar, knownTimeZone: Self.zone("America/New_York"))
    #expect(try newYorkPeriod.lastDay == Self.day(2026, 7, 15))
    #expect(try newYorkPeriod.contains("2026-07-15 10:00", "America/New_York"))

    let paris = try Self.trip("2026-07-10 00:40", "2026-07-15 01:30", in: "Europe/Paris", longitude: 2.35)
    let parisPeriod = try TripPeriod(trip: paris, calendar: calendar, knownTimeZone: Self.zone("Europe/Paris"))
    #expect(try parisPeriod.firstDay == Self.day(2026, 7, 10))
    #expect(try parisPeriod.lastDay == Self.day(2026, 7, 15))
    #expect(try !parisPeriod.contains("2026-07-09 12:00", "Europe/Paris"))

    let samoa = try Self.trip("2026-07-10 10:00", "2026-07-12 18:00", in: "Pacific/Apia", longitude: -171.76)
    let samoaPeriod = try TripPeriod(trip: samoa, calendar: calendar, knownTimeZone: Self.zone("Pacific/Apia"))
    #expect(try samoaPeriod.firstDay == Self.day(2026, 7, 10))
  }

  /// 알려진 한계 (b): 시간대를 알아도 중심점(파리)의 시간대 하나로 계산해, 런던에서 찍은 첫 사진(23:30 BST = 00:30 CEST)의
  /// 날이 하루 밀리고 런던 그날 캡처가 빠진다. 정해진 동작이다(docs/ARCHITECTURE.md §4 여행 폴더).
  @Test("여러 시간대 여행은 중심점 시간대로 계산해 다른 시간대 자정 근처 첫 사진의 날이 밀린다(알려진 한계 b)")
  func multiTimeZoneTripLimit() throws {
    let first = try Self.at("2026-07-10 23:30", "Europe/London")
    let last = try Self.at("2026-07-14 18:00", "Europe/Paris")
    let trip = Trip(
      assetIDs: ["a"],
      startDate: first,
      endDate: last,
      center: Coordinate(latitude: 48.86, longitude: 2.35)
    )

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: Self.zone("Europe/Paris"))

    #expect(try period.firstDay == Self.day(2026, 7, 11))
    #expect(try !period.contains("2026-07-10 10:00", "Europe/London"))
  }
}

// MARK: 도우미

extension TripPeriodTests {
  struct DisplayCase: CustomTestStringConvertible, Sendable {
    let zone: String
    let longitude: Double
    let first: String
    let last: String
    /// yyyymmdd.
    let fallbackFirst: Int
    let knownFirst: Int

    init(
      _ zone: String,
      _ longitude: Double,
      _ first: String,
      _ last: String,
      first fallbackFirst: Int,
      known knownFirst: Int
    ) {
      self.zone = zone
      self.longitude = longitude
      self.first = first
      self.last = last
      self.fallbackFirst = fallbackFirst
      self.knownFirst = knownFirst
    }

    var testDescription: String {
      self.zone
    }
  }

  static let seoul = "Asia/Seoul"

  static func seoulCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try self.zone(self.seoul)
    return calendar
  }

  static func zone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  /// "yyyy-MM-dd HH:mm" 또는 "yyyy-MM-dd HH:mm:ss" 를 그 시간대 시각으로 읽는다.
  static func at(_ text: String, _ identifier: String) throws -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = try self.zone(identifier)
    formatter.dateFormat = text.count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
    return try #require(formatter.date(from: text))
  }

  static func trip(_ first: String, _ last: String, in identifier: String, longitude: Double) throws -> Trip {
    try Trip(
      assetIDs: ["a", "b"],
      startDate: self.at(first, identifier),
      endDate: self.at(last, identifier),
      center: Coordinate(latitude: 0, longitude: longitude)
    )
  }

  static func day(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
    try #require(LocalDate(year: year, month: month, day: day))
  }

  /// yyyymmdd.
  static func number(_ day: LocalDate) -> Int {
    day.year * 10000 + day.month * 100 + day.day
  }
}

extension TripPeriod {
  /// 그 시간대 시각이 캡처 조회 범위(끝 제외)에 드는지.
  func contains(_ text: String, _ identifier: String) throws -> Bool {
    let date = try TripPeriodTests.at(text, identifier)
    return self.captureInterval.start <= date && date < self.captureInterval.end
  }
}
