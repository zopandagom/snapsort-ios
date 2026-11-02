import Core
import Foundation
import Testing

struct ExpiringGifticonsTests {
  private let today = gifticonDay(20_261_026)

  @Test("오늘(D-day)과 7일 뒤는 들고, 8일 뒤와 어제 만료는 빠진다")
  func windowBoundary() {
    let items = [
      extractedGifticon("yesterday", expiry: 20_261_025),
      extractedGifticon("today", expiry: 20_261_026),
      extractedGifticon("plus7", expiry: 20_261_102),
      extractedGifticon("plus8", expiry: 20_261_103),
    ]

    let strip = ExpiringGifticons.make(from: items, today: self.today, limit: 20)

    #expect(strip.items.map(\.id) == ["today", "plus7"])
    #expect(strip.count == 2)
    #expect(strip.today == self.today)
  }

  @Test("사용함·확인 중·만료일 모름은 빠진다")
  func dropsUsedCheckingAndUnknown() {
    let items = [
      extractedGifticon("used", expiry: 20_261_027, isUsed: true),
      checkingGifticon("checking"),
      extractedGifticon("unknown", expiry: nil),
      extractedGifticon("kept", expiry: 20_261_027),
    ]

    let strip = ExpiringGifticons.make(from: items, today: self.today, limit: 20)

    #expect(strip.items.map(\.id) == ["kept"])
    #expect(strip.count == 1)
  }

  @Test("빈 입력이면 비어 있다")
  func emptyInput() {
    let strip = ExpiringGifticons.make(from: [], today: self.today, limit: 20)

    #expect(strip.isEmpty)
    #expect(strip.items.isEmpty)
  }

  @Test("만료일 오름차순, 같은 날이면 최신순(생성일 없는 것 뒤) — 기프티콘 목록 남은 것 섹션과 같다")
  func ordersLikeRemainingSection() {
    let items = [
      extractedGifticon("later", expiry: 20_261_030),
      extractedGifticon("noDate", expiry: 20_261_028),
      extractedGifticon("old", expiry: 20_261_028, created: "2026-01-01T00:00:00Z"),
      extractedGifticon("new", expiry: 20_261_028, created: "2026-10-01T00:00:00Z"),
      extractedGifticon("today", expiry: 20_261_026),
    ]

    let strip = ExpiringGifticons.make(from: items, today: self.today, limit: 20)
    let remaining = GifticonExpirySection.sections(of: items, today: self.today).first { $0.kind == .remaining }

    #expect(strip.items.map(\.id) == ["today", "new", "old", "noDate", "later"])
    #expect(strip.items.map(\.id) == remaining?.items.map(\.id))
  }

  @Test("남은 날과 만료일을 싣는다(D-day → 0, 7일 뒤 → 7)")
  func carriesDue() {
    let items = [extractedGifticon("today", expiry: 20_261_026), extractedGifticon("plus7", expiry: 20_261_102)]

    let strip = ExpiringGifticons.make(from: items, today: self.today, limit: 20)

    #expect(strip.items.map(\.due) == [.remaining(days: 0), .remaining(days: 7)])
    #expect(strip.items.map(\.expiryDate) == [gifticonDay(20_261_026), gifticonDay(20_261_102)])
    #expect(strip.items.map(\.item) == items)
  }

  @Test("상한을 넘으면 앞 limit 개만 담고 개수는 전체를 센다")
  func limitKeepsCount() {
    let items = (0 ..< 25).map { index in
      extractedGifticon(String(format: "g%02d", index), expiry: 20_261_026 + index % 6)
    }

    let strip = ExpiringGifticons.make(from: items, today: self.today, limit: 20)
    let unlimited = ExpiringGifticons.make(from: items, today: self.today, limit: 100)

    #expect(strip.count == 25)
    #expect(strip.items.count == 20)
    #expect(strip.items == Array(unlimited.items.prefix(20)))
  }

  @Test("섞인 입력에서 개수가 위젯 오늘 요약과 같다")
  func countMatchesWidgetToday() {
    let items = [
      extractedGifticon("used", expiry: 20_261_027, isUsed: true),
      checkingGifticon("checking"),
      extractedGifticon("unknown", expiry: nil),
      extractedGifticon("yesterday", expiry: 20_261_025),
      extractedGifticon("plus8", expiry: 20_261_103),
      extractedGifticon("today", expiry: 20_261_026),
      extractedGifticon("plus3", expiry: 20_261_029),
      extractedGifticon("plus7", expiry: 20_261_102),
      extractedGifticon("far", expiry: 20_270_101),
    ]
    // 위젯 입력: 미사용 ∧ 추출된 만료일(저장소 `upcomingGifticonExpiries` 와 같은 조건에서 오늘 이후 제한은 요약이 다시 거른다).
    let expiries = items.compactMap { item -> GifticonExpiry? in
      guard !item.isUsed, case let .extracted(info) = item.status, let date = info.expiryDate else { return nil }
      return GifticonExpiry(imageID: item.id, expiryDate: date)
    }

    let strip = ExpiringGifticons.make(from: items, today: self.today, limit: 20)
    let widgetToday = ExpiryWidgetTimeline.summaries(for: expiries, isChecking: false, today: self.today).first

    #expect(strip.count == 3)
    #expect(strip.count == widgetToday?.count)
  }

  @Test("위젯 창 판정의 경계: 0·7 일은 안, -1·8 일은 밖", arguments: [(0, true), (7, true), (-1, false), (8, false)])
  func isInWindowBoundary(offset: Int, expected: Bool) {
    #expect(ExpiryWidgetTimeline.isInWindow(self.today.addingDays(offset), on: self.today) == expected)
  }
}
