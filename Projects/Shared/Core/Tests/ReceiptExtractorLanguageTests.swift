import Core
import Testing

/// 지원 통화 나라의 언어 범위(설계 r3.8~r3.10): 일본어·중국어·유럽 언어의 환불 금액·취소·세금 별도·머리글·주소.
/// OCR 줄·가게 이름은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct ReceiptExtractorLanguageTests {
  @Test(
    "세금 별도 표시는 한글·한자는 부분 문자열, 라틴은 낱말 같음으로 보고 일본어 お支払 는 단계 1 이다",
    arguments: [
      ReceiptPath("A66", ["TOTAL (HT) 10,00 €", "TOTAL (TTC) 12,00 €"], amount: receiptAmount(1200, .eur)),
      ReceiptPath("A67", ["합계(공급가) 8,182", "합계 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A68", ["ローソン", "合計(本体) ¥1,000"]),
      ReceiptPath("A69", ["ローソン", "合計 ¥1,200", "お支払 ¥1,000"], amount: receiptAmount(1000, .jpy)),
      ReceiptPath("A70", ["TOTAL (WEIGHT 1.2KG) $12.50"], amount: receiptAmount(1250, .usd)),
      ReceiptPath("A71", ["TOTAL (NIGHT) $9.00"], amount: receiptAmount(900, .usd)),
      ReceiptPath("두 낱말", ["TOTAL (SANS TVA) 10,00 €"]),
    ]
  )
  func taxExcludedAndJapaneseStageOne(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "환불 금액 복합 라벨·전표 이름·상태 문구·상태 값·머리말은 언어마다 취소 근거다",
    arguments: [
      ReceiptPath("C31", ["ローソン", "返金額 ¥1,100", "合計 ¥1,100"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("C32", ["退款金额 ¥88.00", "合计 ¥88.00", "人民币"], amount: receiptAmount(8800, .cny)),
      ReceiptPath("C33", ["TOTAL REFUND $12.50"], amount: receiptAmount(1250, .usd)),
      ReceiptPath("C34", ["Erstattungsbetrag 12,50 €", "Summe 12,50 €"], amount: receiptAmount(1250, .eur)),
      ReceiptPath("C35", ["STORNOBELEG", "SUMME 12,50 €"]),
      ReceiptPath("C36", ["RETURN RECEIPT", "TOTAL 12.50"]),
      ReceiptPath("C37", ["STORNO", "Summe 12,50 €"]),
      ReceiptPath("C39", ["TYPE: RETURN", "TOTAL 12.50"]),
      ReceiptPath("C40", ["Vorgang: Storno", "Summe 12,50 €"]),
      ReceiptPath("C41", ["ローソン", "元取引番号 1234", "合計 ¥1,100"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("C61", ["TICKET D'ANNULATION", "TOTAL 12,50 €"], amount: receiptAmount(1250, .eur)),
      ReceiptPath("C62", ["TICKET D\u{2019}ANNULATION", "TOTAL 12,50 €"], amount: receiptAmount(1250, .eur)),
    ]
  )
  func languageCancelEvidence(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled)
    #expect(info.amount == path.amount)
  }

  @Test(
    "라틴 머리말은 번호·날짜 값일 때만, 라틴 상태 값은 3낱말 이하에서 낱말 같음일 때만 취소다",
    arguments: [
      ReceiptPath("C43", ["Original Receipt #1234", "TOTAL 12.50"], isCancelled: true),
      ReceiptPath("C44", ["Orig Trans: 0012 3456", "TOTAL 12.50"], isCancelled: true),
      ReceiptPath("C51", ["Status: Cancellation", "TOTAL 9.00"], isCancelled: true),
      ReceiptPath("C52", ["Type: Remboursement", "TOTAL 12,50 €"], isCancelled: true),
      ReceiptPath("C53", ["Vorgang: Stornierung", "Summe 12,50 €"], isCancelled: true),
      ReceiptPath("C54", ["Status: Voided Transaction", "TOTAL 9.00"], isCancelled: true),
      ReceiptPath("C56", ["Orig. Trans: 0012", "TOTAL 12.50"], isCancelled: true),
      ReceiptPath("C57", ["Original Receipt No. 1234", "TOTAL 12.50"], isCancelled: true),
      ReceiptPath("C58", ["Original Receipt Nr. 1234", "Summe 12,50 €"], isCancelled: true),
      ReceiptPath("C59", ["Orig Trans Date: 10/01/2026", "TOTAL 12.50"], isCancelled: true),
      ReceiptPath("C60", ["Status: (CANCELLED)", "TOTAL 9.00"], isCancelled: true),
      ReceiptPath("A72", ["Type: Annule\u{301}"], isCancelled: true),
      ReceiptPath("C38", ["합계 9,000", "STORNO"]),
      ReceiptPath("C42", ["ORIGINAL RECEIPT REQUIRED FOR RETURNS", "TOTAL $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("C45", ["Original transaction date required", "TOTAL 9.00"]),
      ReceiptPath("C46", ["Status: Cancellable", "TOTAL 9.00"]),
      ReceiptPath("C47", ["TYPE: RETURNABLE", "TOTAL 9.00"]),
      ReceiptPath("C48", ["Gutschrift 0,25 €", "TOTAL 12,50 €"], amount: receiptAmount(1250, .eur)),
      ReceiptPath("C49", ["Erstattung 0,25 €", "TOTAL 12,50 €"], amount: receiptAmount(1250, .eur)),
      ReceiptPath("C50", ["Return", "Order Details", "TOTAL 45.20"]),
      ReceiptPath("C55", ["Status: Refund eligible within 30 days", "TOTAL 9.00"]),
    ]
  )
  func latinNoticesAreNotCancellations(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled == path.isCancelled)
    if path.amount != nil {
      #expect(info.amount == path.amount)
    }
  }

  @Test(
    "유럽 머리글·인사·머리말·주소 줄은 위쪽 줄 가게가 아니고, 라틴 지명이 아닌 숫자 시작 줄은 우편번호가 아니다",
    arguments: [
      ReceiptPath("S53", ["KASSENBON", "SUMME 12,50 €"]),
      ReceiptPath("S54", ["SCONTRINO FISCALE", "Bar Roma", "TOTALE 12,50 €"], storeName: "Bar Roma"),
      ReceiptPath("S55", ["Thank you for shopping", "TOTAL 9.00"]),
      ReceiptPath("S55 회귀 Welcome", ["Welcome Mart", "TOTAL 9.00"]),
      ReceiptPath("S56", ["Kasse 3", "SUMME 12,50 €"]),
      ReceiptPath("S57", ["Hauptstraße 12", "10115 Berlin", "SUMME 12,50 €"]),
      ReceiptPath("S57 회귀 우편번호", ["10115 Berlin", "TOTAL 9.00"]),
      ReceiptPath("S57 회귀 Via", ["Via Roma Pizza", "TOTALE 12,50 €"], storeName: "Via Roma Pizza"),
      ReceiptPath("S58", ["2580 ローソン渋谷", "合計 ¥1,100"], storeName: "2580 ローソン渋谷"),
      ReceiptPath("S59", ["Bahnhofstr. 5", "SUMME 12,50 €"]),
      ReceiptPath("S60", ["Marktplatz Café", "SUMME 12,50 €"], storeName: "Marktplatz Café"),
      ReceiptPath("S61", ["Return", "Order Details", "TOTAL 45.20"]),
      ReceiptPath("S62", ["Card Type: VISA", "VISA", "Auth Code 123456", "TOTAL 12.50"]),
      ReceiptPath("S63", ["Entry Method: Chip", "Acct ****1234", "TOTAL 12.50"]),
      ReceiptPath("S64 Cardiff", ["Cardiff Cafe", "TOTAL 12.50"], storeName: "Cardiff Cafe"),
      ReceiptPath("S64 Merchant", ["Merchant Square", "TOTAL 12.50"], storeName: "Merchant Square"),
      ReceiptPath("S65 Terminal", ["Terminal 5 Cafe", "TOTAL 12.50"], storeName: "Terminal 5 Cafe"),
      ReceiptPath("일본 카드 머리말", ["承認番号:A12345", "ローソン", "合計 ¥1,100"], storeName: "ローソン"),
    ]
  )
  func europeanUpperLines(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }
}
