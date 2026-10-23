import Core
import Testing

/// 띄어 쓰지 않는 표기·덧말·부가 금액에서 금액을 잘못 고르는 경로(설계 r3.4~r3.6, A31~A55). OCR 줄은 지어낸 텍스트다
/// (docs/CONVENTIONS.md §3). 엔 영수증은 `¥` 를 엔으로 정하도록 가나 줄 "ローソン" 을 함께 둔다.
struct ReceiptExtractorRemarkTests {
  @Test(
    "한글·한자·가나 끊는 말은 붙여 써도 범위를 끊고, 税込 는 끊지 않는다",
    arguments: [
      ReceiptPath("A31", ["ローソン", "合計 ¥1,100 (内消費税等 ¥100)"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A32", ["ローソン", "合計 ¥1,100(内消費税等¥100)"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A33", ["합계 9,000 (카드할인 1,000)"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A34", ["결제금액 9,000 포함부가세 818"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A35 뒤", ["ローソン", "合計 ¥1,234 税込"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A35 괄호", ["ローソン", "合計(税込) ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A35 붙음", ["ローソン", "税込合計 ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A35 꼬리 말", ["ローソン", "合計 税込 ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A36", ["超市 人民币", "合计 ¥88.00 找零 ¥12.00"], amount: receiptAmount(8800, .cny)),
      ReceiptPath("A37", ["ローソン", "合計 ¥1,100 お預かり ¥2,000"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A38", ["合计 金额 ¥88.00", "人民币"], amount: receiptAmount(8800, .cny)),
    ]
  )
  func cutsAttachedCJKWords(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "라틴 끊는 말은 복수형까지 낱말로 맞추고 TAXI 같은 다른 낱말 속 글자에는 걸리지 않는다(A39)",
    arguments: [
      ReceiptPath("A39 taxes", ["TOTAL $45.20 TAXES 3.00"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A39 tips", ["TOTAL $45.20 TIPS 5.00"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A39 TAXI", ["TOTAL $45.20", "TAXI SERVICE"], amount: receiptAmount(4520, .usd)),
    ]
  )
  func latinCutWords(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "같은 값 후보는 그 통화로 읽히는 토큰을 쓰고, 음수 후보가 하나라도 있으면 취소다",
    arguments: [
      ReceiptPath("A40", ["합계 9.000", "합계 9,000원"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A41", ["합계 -9.000", "합계 9,000"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("A42", ["Total 1.234,56 €", "Total 1.234,56 €"], amount: receiptAmount(123_456, .eur)),
    ]
  )
  func sameValueCandidates(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.amount == path.amount)
    #expect(info.isCancelled == path.isCancelled)
  }

  @Test(
    "금액 하나뿐인 괄호 밖의 덧말은 숫자가 있어도 지우고, 첫 금액 뒤 글자 낱말에서 끊는다",
    arguments: [
      ReceiptPath("A43", ["ローソン", "合計 ¥1,080 (10%対象 ¥1,000 内消費税等 ¥80)"], amount: receiptAmount(1080, .jpy)),
      ReceiptPath("A44", ["TOTAL $45.20 (TAXABLE 40.00)"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A45", ["합계 9,000 (봉사료 900)"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A46", ["ローソン", "合計 ¥1,080 10%対象 ¥1,000"], amount: receiptAmount(1080, .jpy)),
      ReceiptPath("A46b VISA", ["TOTAL $45.20 VISA 45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A46b 카드", ["합계 9,000 카드 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A46b GIFT", ["TOTAL $45.20 GIFT CARD 10.00"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A46c", ["ローソン", "合計 ¥1,080 (10%対象 ¥1,000"], amount: receiptAmount(1080, .jpy)),
      ReceiptPath("A46d ITEMS", ["TOTAL 2 ITEMS $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A46d 点", ["ローソン", "合計 3点 ¥1,100"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("회귀 C8", ["합계 (9,000)"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("회귀 A6", ["합계 3개 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func removesRemarksAndCutsAfterFirstAmount(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.amount == path.amount)
    #expect(info.isCancelled == path.isCancelled)
  }

  @Test(
    "할인 뒤 금액이 붙은 줄은 값이 갈린 것으로 보아 낮은 단계로 내려가지 않고 금액 모름이다",
    arguments: [
      ReceiptPath("A47", ["결제금액 10,000 할인후 9,000"]),
      ReceiptPath("A47 띄움", ["결제금액 10,000 할인 후 9,000"]),
      ReceiptPath("A48", ["ローソン", "合計 ¥1,200 値引後 ¥1,000"]),
      ReceiptPath("A48b", ["합계 10,000", "결제금액 10,000 할인 후 9,000"]),
      ReceiptPath("after", ["TOTAL $50.00 AFTER DISCOUNT $45.00"]),
      ReceiptPath("A55", ["결제금액 9,000 할인후원 1,000"]),
    ]
  )
  func afterDiscountSplitsLine(_ path: ReceiptPath) {
    #expect(path.extracted.amount == nil)
  }

  @Test(
    "첫 금액과 다음 금액 사이에 후·後 가 어디든 붙어 있거나 after·net 낱말이 있으면 그 줄은 값이 갈린다(r3.8)",
    arguments: [
      ReceiptPath("A56", ["결제금액 10,000 쿠폰할인후 9,000"]),
      ReceiptPath("A57", ["ローソン", "合計 ¥1,200 会員割引後 ¥1,000"]),
      ReceiptPath("A58", ["ローソン", "合計 ¥1,200 クーポン値引後 ¥1,000"]),
      ReceiptPath("A59", ["ローソン", "合計 ¥1,200 割引値引後 ¥1,000"]),
      ReceiptPath("A60", ["결제금액 10,000 할인적용후 9,000"]),
      ReceiptPath("A61", ["결제금액 10,000 포인트사용후 9,000"]),
      ReceiptPath("A62", ["결제금액 10,000 (할인후 9,000)"]),
      ReceiptPath("A63", ["합계 10,000", "결제금액 10,000 쿠폰할인후 9,000"]),
      ReceiptPath("A65 net", ["TOTAL $50.00 NET 45.00"]),
      ReceiptPath("A73", ["결제금액 10,000 할인 1,000 할인후 9,000"]),
      ReceiptPath("A74", ["TOTAL $50.00 DISCOUNT $5.00 TOTAL AFTER DISCOUNT $45.00"]),
      // 받아들인 빈 값: 두 금액 사이 "후불" 도 후가 들어 있어 금액 모름이다.
      ReceiptPath("A54", ["결제금액 9,000 후불결제 9,000"]),
    ]
  )
  func afterDiscountBetweenAmounts(_ path: ReceiptPath) {
    #expect(path.extracted.amount == nil)
  }

  @Test("다음 금액이 없거나 NETWORK 처럼 다른 낱말이면 할인 뒤 표시가 아니다(A64·A65)")
  func noAfterDiscountWithoutNextAmount() {
    #expect(extractReceipt(["결제금액 9,000 후불결제"]).amount == receiptAmount(9000, .krw))
    #expect(extractReceipt(["합계 9,000 할인 1,000"]).amount == receiptAmount(9000, .krw))
    #expect(extractReceipt(["TOTAL $45.20 NETWORK 3.00"]).amount == receiptAmount(4520, .usd))
  }

  @Test(
    "세금 별도 표시가 붙은 라벨은 라벨 줄이 아니다",
    arguments: [
      ReceiptPath("A49", ["ローソン", "合計(税抜) ¥1,000", "合計(税込) ¥1,100"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A49b", ["합계(부가세 별도) 9,000"]),
      ReceiptPath("excl", ["TOTAL (EXCL. TAX) $40.00"]),
    ]
  )
  func taxExcludedLabelsAreNotLabels(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "첫 묶음 안에 서로 다른 금액이 있으면 금액 모름이고 같은 값 두 번이면 그 값이다",
    arguments: [
      ReceiptPath("A50 엔", ["ローソン", "合計 ¥1,080 ¥80"]),
      ReceiptPath("A50 같은 값", ["TOTAL $45.20 $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A50 수량", ["합계 150 9,000"]),
      ReceiptPath("A50 연도", ["결제금액 2026 9,000"]),
      ReceiptPath("A50 두 통화", ["TOTAL 45.20 USD 61,234 KRW"]),
    ]
  )
  func differentAmountsInFirstGroup(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "지원하지 않는 통화 표시가 붙은 금액과 그 영수증의 표시 없는 금액은 통화 모름이다",
    arguments: [
      ReceiptPath("A51", ["COFFEE $4.50", "Amount Due: 45.20 CAD"]),
      ReceiptPath("A52", ["TOTAL CAD 45.20"]),
      ReceiptPath("A53", ["TIP $2.00", "TOTAL £12.00"]),
      ReceiptPath("A53 표시 없음", ["TIP $2.00", "SERVICE £1.00", "TOTAL 12.00"]),
    ]
  )
  func unsupportedCurrencyIsUnknown(_ path: ReceiptPath) {
    #expect(path.extracted.amount == nil)
  }
}
