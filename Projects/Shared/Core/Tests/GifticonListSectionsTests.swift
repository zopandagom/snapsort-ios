import Core
import Foundation
import Testing

struct GifticonListSectionsTests {
  @Test("탭에 맞는 사용 여부의 항목만 고른다")
  func filtersByUsage() {
    let items = [
      extractedGifticon("unused", expiry: 20_261_231),
      extractedGifticon("used", expiry: 20_261_231, isUsed: true),
      checkingGifticon("usedChecking", isUsed: true),
    ]

    let unused = Self.sections(items, used: false, sort: .expiry)
    let used = Self.sections(items, used: true, sort: .expiry)

    #expect(Self.ids(unused) == [["unused"]])
    #expect(Self.ids(used) == [["used"], ["usedChecking"]])
  }

  @Test("임박순은 만료 섹션 계산과 같다")
  func expirySortMatchesExpirySections() {
    let items = [
      extractedGifticon("expired", expiry: 20_261_001),
      extractedGifticon("remaining", expiry: 20_261_231),
      extractedGifticon("unknown", expiry: nil),
      checkingGifticon("checking"),
    ]

    let sections = Self.sections(items, used: false, sort: .expiry)

    #expect(sections == .byExpiry(GifticonExpirySection.sections(of: items, today: gifticonDay(20_261_019))))
  }

  @Test("월별은 생성일 달로 묶어 최신순이고 날짜 없음은 맨 뒤다")
  func monthSortGroupsByCreationMonth() {
    let items = [
      extractedGifticon("sep", expiry: 20_261_231, created: "2026-09-10T00:00:00Z"),
      extractedGifticon("noDate", expiry: nil),
      extractedGifticon("octLate", expiry: 20_261_001, created: "2026-10-20T00:00:00Z"),
      checkingGifticon("octEarly", created: "2026-10-01T00:00:00Z"),
    ]

    let sections = Self.sections(items, used: false, sort: .month)

    guard case let .byMonth(months) = sections else {
      Issue.record("월별 섹션이 아니다")
      return
    }
    #expect(months.map(\.month) == [
      ImageMonth(era: 1, year: 2026, month: 10),
      ImageMonth(era: 1, year: 2026, month: 9),
      nil,
    ])
    #expect(months.map { $0.items.map(\.id) } == [["octLate", "octEarly"], ["sep"], ["noDate"]])
    #expect(months[0].items[0] == items[2])
  }

  @Test("같은 시각이라도 달력의 시간대로 월 경계 항목이 다른 달로 간다")
  func monthBoundaryUsesCalendarTimeZone() {
    let items = [extractedGifticon("a", expiry: nil, created: "2026-09-30T15:30:00Z")]

    let seoul = GifticonListSections.sections(
      of: items, used: false, sort: .month, today: gifticonDay(20_261_019), calendar: gregorianCalendar("Asia/Seoul")
    )
    let utc = GifticonListSections.sections(
      of: items, used: false, sort: .month, today: gifticonDay(20_261_019), calendar: gregorianCalendar("UTC")
    )

    guard case let .byMonth(seoulMonths) = seoul, case let .byMonth(utcMonths) = utc else {
      Issue.record("월별 섹션이 아니다")
      return
    }
    #expect(seoulMonths.map(\.month) == [ImageMonth(era: 1, year: 2026, month: 10)])
    #expect(utcMonths.map(\.month) == [ImageMonth(era: 1, year: 2026, month: 9)])
  }

  @Test("고른 항목이 없으면 섹션이 없다")
  func emptySelectionHasNoSections() {
    let items = [extractedGifticon("unused", expiry: 20_261_231)]

    #expect(Self.sections(items, used: true, sort: .expiry) == .byExpiry([]))
    #expect(Self.sections(items, used: true, sort: .month) == .byMonth([]))
  }

  private static func sections(_ items: [GifticonListItem], used: Bool, sort: GifticonSort) -> GifticonListSections {
    GifticonListSections.sections(
      of: items,
      used: used,
      sort: sort,
      today: gifticonDay(20_261_019),
      calendar: gregorianCalendar("Asia/Seoul")
    )
  }

  private static func ids(_ sections: GifticonListSections) -> [[String]] {
    switch sections {
    case let .byExpiry(sections): sections.map { $0.items.map(\.id) }
    case let .byMonth(sections): sections.map { $0.items.map(\.id) }
    }
  }
}
