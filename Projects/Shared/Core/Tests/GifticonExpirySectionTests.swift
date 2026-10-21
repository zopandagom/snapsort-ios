import Core
import Foundation
import Testing

struct GifticonExpirySectionTests {
  @Test("남은 것 → 만료됨 → 만료일 모름 → 확인 중 순서이고 빈 섹션은 뺀다")
  func ordersSectionsAndDropsEmpty() {
    let items = [
      checkingGifticon("checking"),
      extractedGifticon("unknown", expiry: nil),
      extractedGifticon("expired", expiry: 20_261_018),
      extractedGifticon("remaining", expiry: 20_261_020),
    ]

    let sections = GifticonExpirySection.sections(of: items, today: gifticonDay(20_261_019))
    let withoutExpired = GifticonExpirySection.sections(
      of: items.filter { $0.id != "expired" },
      today: gifticonDay(20_261_019)
    )

    #expect(sections.map(\.kind) == [.remaining, .expired, .unknownExpiry, .checking])
    #expect(sections.map { $0.items.map(\.id) } == [["remaining"], ["expired"], ["unknown"], ["checking"]])
    #expect(withoutExpired.map(\.kind) == [.remaining, .unknownExpiry, .checking])
    #expect(GifticonExpirySection.sections(of: [], today: gifticonDay(20_261_019)).isEmpty)
  }

  @Test("남은 것은 가까운 만료일부터, 만료됨은 최근 만료부터다")
  func sortsByExpiry() {
    let items = [
      extractedGifticon("later", expiry: 20_270_101),
      extractedGifticon("today", expiry: 20_261_019),
      extractedGifticon("soon", expiry: 20_261_020),
      extractedGifticon("longAgo", expiry: 20_250_101),
      extractedGifticon("yesterday", expiry: 20_261_018),
    ]

    let sections = GifticonExpirySection.sections(of: items, today: gifticonDay(20_261_019))

    #expect(sections.map { $0.items.map(\.id) } == [["today", "soon", "later"], ["yesterday", "longAgo"]])
  }

  @Test("오늘 만료는 남은 것 맨 앞이다")
  func expiringTodayIsFirstRemaining() {
    let items = [extractedGifticon("tomorrow", expiry: 20_270_101), extractedGifticon("today", expiry: 20_261_231)]

    let sections = GifticonExpirySection.sections(of: items, today: gifticonDay(20_261_231))

    #expect(sections.first?.kind == .remaining)
    #expect(sections.first?.items.map(\.id) == ["today", "tomorrow"])
  }

  @Test("같은 만료일·만료일 없는 섹션 안에서는 최신순이고 생성일 없는 것은 뒤, 같으면 식별자 순이다")
  func tiesAreNewestFirst() {
    let items = [
      extractedGifticon("noDateB", expiry: 20_261_231),
      extractedGifticon("old", expiry: 20_261_231, created: "2026-01-01T00:00:00Z"),
      extractedGifticon("noDateA", expiry: 20_261_231),
      extractedGifticon("new", expiry: 20_261_231, created: "2026-10-01T00:00:00Z"),
      extractedGifticon("sameB", expiry: 20_261_231, created: "2026-05-01T00:00:00Z"),
      extractedGifticon("sameA", expiry: 20_261_231, created: "2026-05-01T00:00:00Z"),
      extractedGifticon("unknownOld", expiry: nil, created: "2026-01-01T00:00:00Z"),
      extractedGifticon("unknownNew", expiry: nil, created: "2026-10-01T00:00:00Z"),
      checkingGifticon("checkingNoDate"),
      checkingGifticon("checkingNew", created: "2026-10-01T00:00:00Z"),
    ]

    let sections = GifticonExpirySection.sections(of: items, today: gifticonDay(20_261_019))

    #expect(sections.map { $0.items.map(\.id) } == [
      ["new", "sameA", "sameB", "old", "noDateA", "noDateB"],
      ["unknownNew", "unknownOld"],
      ["checkingNew", "checkingNoDate"],
    ])
  }

  @Test("같은 시각이라도 시간대에 따라 오늘이 달라 섹션이 바뀐다(서울 vs 로스앤젤레스)")
  func timeZoneBoundary() throws {
    // 2026-12-31 15:30 UTC 는 서울 2027-01-01, 로스앤젤레스 2026-12-31 이다.
    let now = try Date("2026-12-31T15:30:00Z", strategy: .iso8601)
    let items = [extractedGifticon("a", expiry: 20_261_231)]

    let seoulToday = LocalDate(now, calendar: gregorianCalendar("Asia/Seoul"))
    let laToday = LocalDate(now, calendar: gregorianCalendar("America/Los_Angeles"))
    let seoul = GifticonExpirySection.sections(of: items, today: seoulToday)
    let losAngeles = GifticonExpirySection.sections(of: items, today: laToday)

    #expect(seoul.map(\.kind) == [.expired])
    #expect(GifticonDue(expiryDate: gifticonDay(20_261_231), today: seoulToday) == .expired(daysAgo: 1))
    #expect(losAngeles.map(\.kind) == [.remaining])
    #expect(GifticonDue(expiryDate: gifticonDay(20_261_231), today: laToday) == .remaining(days: 0))
  }

  @Test("기기 달력이 일본력이어도 오늘은 서기로 센다")
  func japaneseCalendarToday() throws {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let now = try Date("2026-12-31T03:00:00Z", strategy: .iso8601)

    let today = LocalDate(now, calendar: japanese)
    let sections = GifticonExpirySection.sections(of: [extractedGifticon("a", expiry: 20_261_231)], today: today)

    #expect(today == gifticonDay(20_261_231))
    #expect(sections.map(\.kind) == [.remaining])
  }
}
