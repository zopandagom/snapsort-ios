import Core
import Foundation
import Testing

struct ReceiptListSectionsTests {
  @Test("월별: Asia/Seoul 자정 경계로 나눈다")
  func monthBoundaryInSeoul() {
    let items = [
      extractedReceipt("oct", created: "2026-10-31T14:59:59Z"),
      extractedReceipt("nov", created: "2026-10-31T15:00:00Z"),
    ]

    let months = Self.months(items, timeZone: "Asia/Seoul")

    #expect(months.map(\.month) == [
      ImageMonth(era: 1, year: 2026, month: 11),
      ImageMonth(era: 1, year: 2026, month: 10),
    ])
    #expect(months.map { $0.items.map(\.id) } == [["nov"], ["oct"]])
  }

  @Test(
    "월별: America/New_York 은 같은 시각을 다른 달로 나누고, DST 시작·끝 달의 자정에서 나눈다",
    arguments: [
      ("2026-11-01T03:59:59Z", 10), ("2026-11-01T04:00:00Z", 11), ("2026-11-01T05:30:00Z", 11), (
        "2026-11-01T06:30:00Z",
        11
      ),
      ("2026-03-01T04:59:59Z", 2), ("2026-03-01T05:00:00Z", 3), ("2026-04-01T03:59:59Z", 3), (
        "2026-04-01T04:00:00Z",
        4
      ),
    ]
  )
  func monthBoundaryInNewYork(_ created: String, _ month: Int) {
    let months = Self.months([extractedReceipt("a", created: created)], timeZone: "America/New_York")
    #expect(months.map(\.month) == [ImageMonth(era: 1, year: 2026, month: month)])
  }

  @Test("같은 목록도 달력 시간대가 바뀌면 월 섹션이 바뀐다")
  func timeZoneChangesSections() {
    let items = [extractedReceipt("a", created: "2026-10-31T20:00:00Z")]

    #expect(Self.months(items, timeZone: "Asia/Seoul").map(\.month) == [ImageMonth(era: 1, year: 2026, month: 11)])
    #expect(Self.months(items, timeZone: "America/New_York").map(\.month) == [ImageMonth(
      era: 1,
      year: 2026,
      month: 10
    )])
  }

  @Test("생성일 없는 영수증은 맨 뒤 '날짜 없음' 섹션이고 합계를 낸다")
  func undatedSectionIsLastWithTotals() {
    let items = [
      extractedReceipt("undated", amount: receiptAmount(8000, .krw)),
      extractedReceipt("oct", created: "2026-10-15T03:00:00Z", amount: receiptAmount(9000, .krw)),
    ]

    let months = Self.months(items, timeZone: "Asia/Seoul")

    #expect(months.map(\.month) == [ImageMonth(era: 1, year: 2026, month: 10), nil])
    #expect(months.last?.totals.currencies == [ReceiptCurrencyTotal(currency: .krw, amount: 8000, count: 1)])
  }

  @Test("합계는 통화별로 따로 더하고 영수증 수가 많은 통화부터, 같으면 원·달러·엔·유로·위안 순이다")
  func totalsPerCurrency() throws {
    let totals = ReceiptTotals(items: [
      extractedReceipt("eur", amount: receiptAmount(1250, .eur)),
      extractedReceipt("usd1", amount: receiptAmount(4520, .usd)),
      extractedReceipt("usd2", amount: receiptAmount(1000, .usd)),
      extractedReceipt("cny", amount: receiptAmount(8800, .cny)),
      extractedReceipt("jpy", amount: receiptAmount(1234, .jpy)),
      extractedReceipt("krw", amount: receiptAmount(9000, .krw)),
    ])

    #expect(totals.currencies.map(\.currency) == [.usd, .krw, .jpy, .eur, .cny])
    #expect(try totals.currencies.first == ReceiptCurrencyTotal(
      currency: .usd,
      amount: #require(Decimal(string: "55.20")),
      count: 2
    ))
    #expect(try totals.currencies.map(\.amount) == [
      #require(Decimal(string: "55.20")), 9000, 1234, #require(Decimal(string: "12.50")),
      #require(Decimal(string: "88.00")),
    ])
  }

  @Test("취소·금액 모름·확인 중은 합계에 넣지 않고, 금액 모름 수와 확인 중 수를 따로 세며 취소는 어느 수에도 넣지 않는다")
  func excludesCancelledUnknownAndChecking() {
    let totals = ReceiptTotals(items: [
      extractedReceipt("paid", amount: receiptAmount(9000, .krw)),
      extractedReceipt("cancelled", amount: receiptAmount(4500, .krw), isCancelled: true),
      extractedReceipt("cancelledUnknown", amount: nil, isCancelled: true),
      extractedReceipt("unknown1", amount: nil),
      extractedReceipt("unknown2", store: nil, amount: nil),
      checkingReceipt("checking"),
    ])

    #expect(totals.currencies == [ReceiptCurrencyTotal(currency: .krw, amount: 9000, count: 1)])
    #expect(totals.unknownAmountCount == 2)
    #expect(totals.checkingCount == 1)
  }

  @Test("합계는 최소 단위를 Decimal 로 더해 소수 오차가 없고 Int 를 넘는 합도 정확하다")
  func totalsAreExact() {
    let cents = ReceiptTotals(items: [
      extractedReceipt("a", amount: receiptAmount(10, .usd)),
      extractedReceipt("b", amount: receiptAmount(20, .usd)),
    ])
    #expect(cents.currencies.first?.amount == Decimal(string: "0.30"))

    let maximum = receiptAmount(ReceiptAmount.maximumMinorUnits, .krw)
    let large = ReceiptTotals(items: (0 ..< 10000).map { extractedReceipt("\($0)", amount: maximum) })
    #expect(large.currencies.first?.amount == Decimal(string: "10000000000000000"))
    #expect(large.currencies.first?.count == 10000)
  }

  @Test("가게별: 정규화 키로 묶고 가장 최근 영수증이 있는 가게부터, 이름은 가장 최근 영수증의 이름이다")
  func groupsByStoreKey() {
    let items = [
      extractedReceipt(
        "martOld",
        created: "2026-09-01T00:00:00Z",
        store: "(주)예시마트",
        amount: receiptAmount(52300, .krw)
      ),
      extractedReceipt("cafe", created: "2026-10-01T00:00:00Z", store: "카페 예시", amount: receiptAmount(4500, .krw)),
      extractedReceipt("martNew", created: "2026-10-15T00:00:00Z", store: "예시마트", amount: receiptAmount(18000, .krw)),
      extractedReceipt("undatedShop", store: "예시분식", amount: receiptAmount(8000, .krw)),
    ]

    let stores = Self.stores(items)

    #expect(stores.map(\.kind) == [.store(key: "예시마트"), .store(key: "카페예시"), .store(key: "예시분식")])
    #expect(stores.map(\.storeName) == ["예시마트", "카페 예시", "예시분식"])
    #expect(stores.first?.items.map(\.id) == ["martNew", "martOld"])
    #expect(stores.first?.totals.currencies == [ReceiptCurrencyTotal(currency: .krw, amount: 70300, count: 2)])
  }

  @Test("가게별: 가게 모름 → 확인 중 섹션이 맨 뒤이고 합계는 전체 기간이다")
  func unknownAndCheckingSectionsLast() {
    let items = [
      checkingReceipt("checking", created: "2026-10-20T00:00:00Z"),
      extractedReceipt("unknown", created: "2026-10-19T00:00:00Z", store: nil, amount: receiptAmount(12000, .krw)),
      extractedReceipt("symbols", created: "2026-10-18T00:00:00Z", store: "(주)", amount: receiptAmount(1000, .krw)),
      extractedReceipt("may", created: "2026-05-01T00:00:00Z", store: "예시마트", amount: receiptAmount(1000, .krw)),
      extractedReceipt("oct", created: "2026-10-01T00:00:00Z", store: "예시마트", amount: receiptAmount(2000, .krw)),
    ]

    let stores = Self.stores(items)

    #expect(stores.map(\.kind) == [.store(key: "예시마트"), .unknownStore, .checking])
    #expect(stores[0].totals.currencies == [ReceiptCurrencyTotal(currency: .krw, amount: 3000, count: 2)])
    #expect(stores[1].items.map(\.id) == ["unknown", "symbols"])
    #expect(stores[2].totals.checkingCount == 1)
    #expect(stores.map(\.storeName) == ["예시마트", nil, nil])
  }

  @Test("영수증이 없으면 섹션이 비어 있다")
  func emptyItems() {
    for grouping in ReceiptGrouping.allCases {
      #expect(ReceiptListSections.sections(of: [], grouping: grouping, calendar: gregorianCalendar("Asia/Seoul"))
        .isEmpty)
    }
  }

  private static func months(_ items: [ReceiptListItem], timeZone: String) -> [ReceiptMonthSection] {
    guard case let .byMonth(months) = ReceiptListSections.sections(
      of: items,
      grouping: .month,
      calendar: gregorianCalendar(timeZone)
    ) else {
      Issue.record("월별 섹션이 아니다")
      return []
    }
    return months
  }

  private static func stores(_ items: [ReceiptListItem]) -> [ReceiptStoreSection] {
    guard case let .byStore(stores) = ReceiptListSections.sections(
      of: items,
      grouping: .store,
      calendar: gregorianCalendar("Asia/Seoul")
    ) else {
      Issue.record("가게별 섹션이 아니다")
      return []
    }
    return stores
  }
}
