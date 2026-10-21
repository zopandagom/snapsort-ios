import Core
import Testing

/// 테스트의 OCR 줄은 지어낸 텍스트다. 실제 영수증에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).
struct ReceiptExtractorTests {
  @Test("카드 매출전표: 가맹점명 라벨 값이 가게이고 결제금액을 원으로 읽는다")
  func readsCardSlip() {
    let info = extractReceipt([
      "신용카드 매출전표",
      "카드종류 신한",
      "카드번호 1234-56**-****-1234",
      "거래일시 2026-10-21 12:30",
      "가맹점명 예시마트 강남점",
      "사업자번호 000-00-00000",
      "결제금액 9,000원",
      "부가세 818",
      "승인번호 00000000",
    ])

    #expect(info == ReceiptInfo(storeName: "예시마트 강남점", amount: receiptAmount(9000, .krw), isCancelled: false))
  }

  @Test("POS 영수증: 라벨이 없으면 머리글·번호·주소·날짜 줄을 건너뛴 위쪽 첫 줄이 가게이고 합계가 금액이다")
  func readsPOSReceipt() {
    let info = extractReceipt([
      "영수증",
      "(주)예시상사",
      "사업자번호 000-00-00000",
      "서울특별시 중구 세종대로 110",
      "TEL 02-123-4567",
      "2026-10-21 12:30",
      "아메리카노 2 9,000",
      "합계 9,000",
      "부가세 818",
      "승인번호 00000000",
    ])

    #expect(info == ReceiptInfo(storeName: "(주)예시상사", amount: receiptAmount(9000, .krw), isCancelled: false))
  }

  @Test("온라인 결제 캡처: 상태 막대 시각·화면 제목을 건너뛰고 총 결제금액을 읽는다")
  func readsOnlinePaymentCapture() {
    let info = ReceiptExtractor.extract(from: [
      receiptLine("9:41", x: 0.05, y: 0.01, width: 0.1, height: 0.02),
      receiptLine("LTE", x: 0.75, y: 0.01, width: 0.08, height: 0.02),
      receiptLine("100%", x: 0.85, y: 0.01, width: 0.1, height: 0.02),
      receiptLine("결제 상세", y: 0.08),
      receiptLine("예시상점", y: 0.14),
      receiptLine("주문번호 2026102112345", y: 0.2),
      receiptLine("총 결제금액 12,000원", y: 0.26),
    ])

    #expect(info == ReceiptInfo(storeName: "예시상점", amount: receiptAmount(12000, .krw), isCancelled: false))
  }

  @Test("외화 영수증: 위쪽 줄이 가게이고 TOTAL 을 달러로 읽는다")
  func readsForeignReceipt() {
    let info = extractReceipt([
      "EXAMPLE FOODS MARKET",
      "123 MAIN ST",
      "NEW YORK, NY 10001",
      "MILK $3.49",
      "BREAD $5.00",
      "SUBTOTAL $8.49",
      "TAX $0.71",
      "TOTAL $9.20",
    ])

    #expect(info == ReceiptInfo(
      storeName: "EXAMPLE FOODS MARKET",
      amount: receiptAmount(920, .usd),
      isCancelled: false
    ))
  }

  @Test(
    "외화: 통화 표시로 USD·EUR·JPY·CNY 를 판정해 최소 단위로 읽는다",
    arguments: [
      (["TOTAL USD 45.20"], receiptAmount(4520, .usd)),
      (["TOTAL 45.20 USD"], receiptAmount(4520, .usd)),
      (["TOTAL US$45.20"], receiptAmount(4520, .usd)),
      (["TOTAL €12.50"], receiptAmount(1250, .eur)),
      (["TOTAL 12,50 €"], receiptAmount(1250, .eur)),
      (["TOTAL EUR 1.234,56"], receiptAmount(123_456, .eur)),
      (["ローソン", "合計 ¥1,234"], receiptAmount(1234, .jpy)),
      (["合計 1,234円"], receiptAmount(1234, .jpy)),
      (["TOTAL JPY 1,234"], receiptAmount(1234, .jpy)),
      (["合计 88.00元"], receiptAmount(8800, .cny)),
      (["TOTAL CNY 88.00"], receiptAmount(8800, .cny)),
      (["TOTAL RMB 88.00"], receiptAmount(8800, .cny)),
    ]
  )
  func readsForeignCurrencies(_ texts: [String], _ expected: ReceiptAmount) {
    #expect(extractReceipt(texts).amount == expected)
  }

  @Test(
    "¥ 만 있으면 가나·円 이 있을 때 JPY, 元·RMB 면 CNY, 둘 다 없거나 둘 다 있으면 금액 모름",
    arguments: [
      (["ローソン", "TOTAL ¥1,234"], receiptAmount(1234, .jpy) as ReceiptAmount?),
      (["小計 1,000円", "TOTAL ¥1,234"], receiptAmount(1234, .jpy)),
      (["单位 元", "TOTAL ¥88.00"], receiptAmount(8800, .cny)),
      (["PAID IN RMB", "TOTAL ￥88.00"], receiptAmount(8800, .cny)),
      (["TOTAL ¥1,234"], nil),
      (["ローソン", "单位 元", "TOTAL ¥1,234"], nil),
    ]
  )
  func resolvesYenSign(_ texts: [String], _ expected: ReceiptAmount?) {
    #expect(extractReceipt(texts).amount == expected)
  }

  @Test("CA$·A$ 처럼 지원하지 않는 달러는 금액 모름", arguments: ["TOTAL CA$12.00", "TOTAL A$12.00", "TOTAL HK$12.00"])
  func unsupportedDollarIsUnknown(_ text: String) {
    #expect(extractReceipt([text]).amount == nil)
  }

  @Test("한글이 없고 통화 표시도 없으면 금액 모름, 한글이 있으면 원")
  func defaultsToWonOnlyForKoreanReceipt() {
    #expect(extractReceipt(["TOTAL 9,000"]).amount == nil)
    #expect(extractReceipt(["예시마트", "TOTAL 9,000"]).amount == receiptAmount(9000, .krw))
    #expect(extractReceipt(["합계 9,000"]).amount == receiptAmount(9000, .krw))
  }

  @Test("금액 줄의 통화 표시가 영수증의 다른 표시보다 앞서고, 금액 줄에 표시가 없는데 영수증에 두 통화가 있으면 금액 모름")
  func lineMarkWinsOverReceiptMarks() {
    #expect(extractReceipt(["결제금액 USD 45.20", "원화 59,000원"]).amount == receiptAmount(4520, .usd))
    #expect(extractReceipt(["결제금액 45.20", "USD 1 = 1,350원"]).amount == nil)
  }

  @Test("₩ 를 W·\\ 로 읽은 한글 영수증은 원이고, 한글이 없는 영수증의 W 는 통화 표시가 아니다")
  func readsMisreadWonSign() {
    #expect(extractReceipt(["예시마트", "합계 W9,000"]).amount == receiptAmount(9000, .krw))
    #expect(extractReceipt(["예시마트", "합계 \\9,000"]).amount == receiptAmount(9000, .krw))
    #expect(extractReceipt(["NEW SHOP", "TOTAL W9.00"]).amount == nil)
    #expect(extractReceipt(["NEW 9.00"]).amount == nil)
  }
}
