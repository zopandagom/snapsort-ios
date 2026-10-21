import Core
import Foundation
import Testing

/// 시간대를 모르는 여행의 대체 규칙(서울 기기). 기대값은 설계 실험(기기 쪽 여유 2시간·추정 쪽 3시간)으로 확인한 값이다.
extension TripPeriodTests {
  // MARK: 시간대를 모르는 여행 (대체 규칙)

  @Test("대체 규칙은 여행지 첫날·마지막 날 캡처를 빠뜨리지 않는다(뉴욕 여름·파리 여름·상하이·콜카타·LA)")
  func fallbackKeepsTripDays() throws {
    let calendar = try Self.seoulCalendar()
    // 뉴욕: 추정 -5 고정(실제 EDT -4). 마지막 00:30 → 그날 10:00 포함.
    let newYork = try Self.trip("2026-07-10 10:00", "2026-07-15 00:30", in: "America/New_York", longitude: -74.0)
    #expect(try TripPeriod(trip: newYork, calendar: calendar, knownTimeZone: nil)
      .contains("2026-07-15 10:00", "America/New_York"))
    // 파리: 추정 0 고정(실제 CEST +2). 첫 00:40·마지막 01:30 → 그날 10:00 포함, 전날 12:00·23:00 도 섞인다.
    let paris = try TripPeriod(
      trip: Self.trip("2026-07-10 00:40", "2026-07-15 01:30", in: "Europe/Paris", longitude: 2.35),
      calendar: calendar,
      knownTimeZone: nil
    )
    for capture in ["2026-07-10 10:00", "2026-07-15 10:00", "2026-07-09 12:00", "2026-07-09 23:00"] {
      #expect(try paris.contains(capture, "Europe/Paris"), "\(capture)")
    }
    // 상하이: 기기 시간대(실제 +8, 기기 +9). 첫 23:30 → 그날 10:00, 마지막 날 23:30 캡처 포함.
    let shanghai = try TripPeriod(
      trip: Self.trip("2026-07-10 23:30", "2026-07-14 18:00", in: "Asia/Shanghai", longitude: 121.47),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(try shanghai.contains("2026-07-10 10:00", "Asia/Shanghai"))
    #expect(try shanghai.contains("2026-07-14 23:30", "Asia/Shanghai"))
    // 콜카타: 추정 +6 고정(실제 +5:30). 첫 23:50 → 그날 10:00 포함.
    let kolkata = try Self.trip("2026-07-10 23:50", "2026-07-14 18:00", in: "Asia/Kolkata", longitude: 88.36)
    #expect(try TripPeriod(trip: kolkata, calendar: calendar, knownTimeZone: nil)
      .contains("2026-07-10 10:00", "Asia/Kolkata"))
    // LA: 추정 -8 고정(실제 PDT -7). 첫날 07:30 공항·마지막 날 10:00 포함.
    let losAngeles = try TripPeriod(
      trip: Self.trip("2026-10-10 09:00", "2026-10-15 07:00", in: "America/Los_Angeles", longitude: -118.24),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(try losAngeles.contains("2026-10-10 07:30", "America/Los_Angeles"))
    #expect(try losAngeles.contains("2026-10-15 10:00", "America/Los_Angeles"))
  }

  /// 시드니 1월(실제 +11, 기기 +9)은 실제 차가 기기 쪽 여유 2시간과 딱 같아 범위가 여행지 첫날 00:00 정각에서 시작한다.
  /// 여유를 줄이면 이 테스트가 실패한다(`TripPeriod.deviceTimeZoneUncertainty`).
  @Test("시드니 1월 첫 사진 10:00 이면 범위가 첫날 00:00 정각에서 시작해 그 시각 캡처가 든다(기기 쪽 여유 경계)")
  func sydneyBoundaryIsExactlyMidnight() throws {
    let sydney = "Australia/Sydney"
    let trip = try Self.trip("2027-01-10 10:00", "2027-01-14 18:00", in: sydney, longitude: 151.21)

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: nil)

    #expect(period.timeZone.identifier == Self.seoul)
    #expect(try period.captureInterval.start == Self.at("2027-01-10 00:00", sydney))
    #expect(try period.contains("2027-01-10 00:00", sydney))
    #expect(try !period.contains("2027-01-09 23:59:59", sydney))
    #expect(try period.contains("2027-01-10 00:30", sydney))
    #expect(try period.contains("2027-01-14 23:30", sydney))
    #expect(try !period.contains("2027-01-09 12:00", sydney))
    #expect(try period.captureInterval.end == Self.at("2027-01-15 04:00", sydney))
    #expect(try period.firstDay == Self.day(2027, 1, 10))
    #expect(try period.lastDay == Self.day(2027, 1, 14))
  }

  @Test("기기 시간대와 실제가 2시간 다른 곳도 자정 근처 첫·마지막 날 캡처가 든다(시드니·애들레이드·마가단)")
  func fallbackDeviceZoneTwoHoursOff() throws {
    let calendar = try Self.seoulCalendar()
    let sydney = try TripPeriod(
      trip: Self.trip("2027-01-10 00:30", "2027-01-14 18:00", in: "Australia/Sydney", longitude: 151.21),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(try sydney.contains("2027-01-10 10:00", "Australia/Sydney"))

    let adelaide = try TripPeriod(
      trip: Self.trip("2027-01-10 00:20", "2027-01-14 23:40", in: "Australia/Adelaide", longitude: 138.6),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(try adelaide.contains("2027-01-10 10:00", "Australia/Adelaide"))
    #expect(try adelaide.contains("2027-01-14 23:50", "Australia/Adelaide"))

    let magadan = try TripPeriod(
      trip: Self.trip("2026-07-10 00:30", "2026-07-14 23:30", in: "Asia/Magadan", longitude: 150.8),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(try magadan.contains("2026-07-10 10:00", "Asia/Magadan"))
    #expect(try magadan.contains("2026-07-14 23:50", "Asia/Magadan"))
  }

  @Test("경도 추정이 기기와 1시간 넘게 다르면 추정 고정 오프셋과 3시간 여유를 쓴다(싱가포르·사모아)")
  func fallbackEstimatedOffset() throws {
    let calendar = try Self.seoulCalendar()
    let singapore = try TripPeriod(
      trip: Self.trip("2026-07-10 00:30", "2026-07-14 12:00", in: "Asia/Singapore", longitude: 103.85),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(singapore.timeZone.secondsFromGMT() == 7 * 3600)
    #expect(try singapore.contains("2026-07-10 00:10", "Asia/Singapore"))

    // 날짜변경선 건너편(실제 +13, 추정 -11)도 24시간 차라 하루 경계가 맞아 첫날이 든다.
    let samoa = try TripPeriod(
      trip: Self.trip("2026-07-10 10:00", "2026-07-12 18:00", in: "Pacific/Apia", longitude: -171.76),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(samoa.timeZone.secondsFromGMT() == -11 * 3600)
    #expect(try samoa.contains("2026-07-10 00:30", "Pacific/Apia"))
  }

  @Test("기기 시간대 쪽은 앞뒤 2시간이 섞이고, 첫 사진이 0시~2시면 전날 전체 + 2시간이 섞인다(정해진 동작)")
  func fallbackMixesNeighborHours() throws {
    let calendar = try Self.seoulCalendar()
    let morning = try TripPeriod(
      trip: Self.trip("2026-07-10 09:00", "2026-07-12 18:00", in: Self.seoul, longitude: 126.53),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(morning.timeZone.identifier == Self.seoul)
    #expect(!morning.isTimeZoneKnown)
    #expect(try morning.captureInterval.start == Self.at("2026-07-09 22:00", Self.seoul))
    #expect(try morning.captureInterval.end == Self.at("2026-07-13 02:00", Self.seoul))
    #expect(try morning.contains("2026-07-09 22:30", Self.seoul))
    #expect(try !morning.contains("2026-07-09 21:30", Self.seoul))
    #expect(try morning.contains("2026-07-13 01:30", Self.seoul))
    #expect(try !morning.contains("2026-07-13 02:30", Self.seoul))

    let afterMidnight = try TripPeriod(
      trip: Self.trip("2026-07-10 00:30", "2026-07-12 18:00", in: Self.seoul, longitude: 126.53),
      calendar: calendar,
      knownTimeZone: nil
    )
    #expect(try afterMidnight.captureInterval.start == Self.at("2026-07-08 22:00", Self.seoul))
    #expect(try afterMidnight.contains("2026-07-08 23:00", Self.seoul))
    #expect(try afterMidnight.contains("2026-07-09 10:00", Self.seoul))
  }

  /// 알려진 한계 (a): 시간대를 모르면 기기 시간대·경도 추정이 실제와 다른 곳에서 자정 근처 첫·마지막 사진의 표시 날짜가
  /// 하루 밀린다. 상세를 온라인으로 열어 시간대가 캐시되면(knownTimeZone) 실제 날짜가 된다. 정해진 동작이다.
  @Test(
    "시간대를 모르는 여행은 자정 근처 사진의 표시 날짜가 밀리고, 시간대를 알면 실제 날짜다(알려진 한계 a)",
    arguments: [
      DisplayCase(
        "Australia/Sydney",
        151.21,
        "2027-01-10 00:30",
        "2027-01-14 18:00",
        first: 20_270_109,
        known: 20_270_110
      ),
      DisplayCase(
        "Australia/Adelaide",
        138.6,
        "2027-01-10 00:20",
        "2027-01-14 23:40",
        first: 20_270_109,
        known: 20_270_110
      ),
      DisplayCase("Asia/Magadan", 150.8, "2026-07-10 00:30", "2026-07-14 23:30", first: 20_260_709, known: 20_260_710),
      DisplayCase(
        "Asia/Singapore",
        103.85,
        "2026-07-10 00:30",
        "2026-07-14 12:00",
        first: 20_260_709,
        known: 20_260_710
      ),
      DisplayCase("Europe/Paris", 2.35, "2026-07-10 00:40", "2026-07-15 01:30", first: 20_260_709, known: 20_260_710),
      DisplayCase(
        "Pacific/Apia",
        -171.76,
        "2026-07-10 10:00",
        "2026-07-12 18:00",
        first: 20_260_709,
        known: 20_260_710
      ),
    ]
  )
  func fallbackDisplayShift(display: DisplayCase) throws {
    let trip = try Self.trip(display.first, display.last, in: display.zone, longitude: display.longitude)
    let calendar = try Self.seoulCalendar()

    let fallback = TripPeriod(trip: trip, calendar: calendar, knownTimeZone: nil)
    let known = try TripPeriod(trip: trip, calendar: calendar, knownTimeZone: Self.zone(display.zone))

    #expect(Self.number(fallback.firstDay) == display.fallbackFirst)
    #expect(Self.number(known.firstDay) == display.knownFirst)
  }

  @Test("시간대를 모르는 뉴욕 여름 마지막 00:30 은 마지막 날이 하루 이르고, 알면 실제 날짜다(알려진 한계 a)")
  func fallbackLastDayShift() throws {
    let newYork = "America/New_York"
    let trip = try Self.trip("2026-07-10 10:00", "2026-07-15 00:30", in: newYork, longitude: -74.0)
    let calendar = try Self.seoulCalendar()

    #expect(try TripPeriod(trip: trip, calendar: calendar, knownTimeZone: nil).lastDay == Self.day(2026, 7, 14))
    #expect(try TripPeriod(trip: trip, calendar: calendar, knownTimeZone: Self.zone(newYork)).lastDay
      == Self.day(2026, 7, 15))
  }

  @Test("마지막 시각이 첫 시각보다 앞서도 멈추지 않고 첫 시각 기준 범위를 만든다")
  func endBeforeStartDoesNotTrap() throws {
    let start = try Self.at("2026-07-10 09:00", Self.seoul)
    let trip = Trip(
      assetIDs: ["a"],
      startDate: start,
      endDate: start.addingTimeInterval(-3600),
      center: Coordinate(latitude: 33.5, longitude: 126.53)
    )

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: nil)

    #expect(period.captureInterval.start < start)
    #expect(period.captureInterval.end > start)
  }

  @Test("중심점 경도가 유한하지 않으면 기기 시간대를 쓴다")
  func nonFiniteCenterUsesDeviceTimeZone() throws {
    let start = try Self.at("2026-07-10 09:00", Self.seoul)
    let trip = Trip(assetIDs: ["a"], startDate: start, endDate: start, center: Coordinate(latitude: 0, longitude: .nan))

    let period = try TripPeriod(trip: trip, calendar: Self.seoulCalendar(), knownTimeZone: nil)

    #expect(period.timeZone.identifier == Self.seoul)
    #expect(try period.captureInterval.start == Self.at("2026-07-09 22:00", Self.seoul))
  }
}
