import Core
import Testing

/// 나라별 숫자·음수 표기 관례(설계 r3.20~r3.22, A76~A85·C108~C112). OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
/// 엔 영수증은 `¥` 를 엔으로 정하도록 가나 줄 "ローソン" 을, 위안 영수증은 "元" 줄을 함께 둔다.
struct ReceiptExtractorNotationTests {
  @Test(
    "좁은 공백·아포스트로피 천 단위는 한 수로 읽고, 일반 공백으로 나뉜 1~3자리 + 3자리 수는 갈린다",
    arguments: [
      ReceiptPath("A76", ["TOTAL 1 234,56 €"]),
      ReceiptPath("A77 NBSP", ["TOTAL 1\u{00A0}234,56 €"], amount: receiptAmount(123_456, .eur)),
      ReceiptPath("A77 좁은 NBSP", ["TOTAL 1\u{202F}234,56 €"], amount: receiptAmount(123_456, .eur)),
      ReceiptPath("A77 얇은 공백", ["TOTAL 1\u{2009}234,56 €"], amount: receiptAmount(123_456, .eur)),
      ReceiptPath("A78 수량", ["합계 2 900"]),
      ReceiptPath("A78 천 단위", ["TOTAL 12 345 €"]),
      ReceiptPath("A78 수량 원", ["합계 2 900원"]),
      ReceiptPath("A78 수량 유로", ["TOTAL 2 900 €"]),
      ReceiptPath("A78b 쉼표", ["합계 3 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A78b ITEMS", ["TOTAL 2 ITEMS $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A78b A6", ["합계 3개 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A78b A16", ["합계 3"]),
      ReceiptPath("A78c 엔", ["ローソン", "合計 2 ¥450"], amount: receiptAmount(450, .jpy)),
      ReceiptPath("A78c 달러", ["TOTAL 3 $125.00"], amount: receiptAmount(12500, .usd)),
      ReceiptPath("A78c 원", ["합계 1 ₩900"], amount: receiptAmount(900, .krw)),
      ReceiptPath("A79 코드", ["TOTAL EUR 1'234.50"], amount: receiptAmount(123_450, .eur)),
      ReceiptPath("A79 곡선", ["TOTAL 1’234.50 €"], amount: receiptAmount(123_450, .eur)),
    ]
  )
  func thousandsSeparators(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "끝 줄표는 원·달러·유로만 음수이고 엔·위안·통화 모름이면 금액 끝 표시다",
    arguments: [
      ReceiptPath("A80 줄표", ["ローソン", "合計 ¥1,100-"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A80 마이너스", ["ローソン", "お会計 ¥3,300−"], amount: receiptAmount(3300, .jpy)),
      ReceiptPath("A80 円", ["ローソン", "合計 1,100円-"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A80 장음", ["ローソン", "合計 ¥1,100ー"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A80 전각", ["ローソン", "合計 ￥１，１００－"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A81 원", ["합계 9,000-"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("A81 달러", ["TOTAL $12.50-"], amount: receiptAmount(1250, .usd), isCancelled: true),
      ReceiptPath("A81 유로", ["TOTAL 12,50 €-"], amount: receiptAmount(1250, .eur), isCancelled: true),
      ReceiptPath("A82", ["合計 ¥1,100-"]),
      ReceiptPath("C108", ["ローソン", "合計 ¥1,100-", "お預り ¥2,000", "お釣り ¥900-"], amount: receiptAmount(1100, .jpy)),
    ]
  )
  func trailingDash(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.amount == path.amount)
    #expect(info.isCancelled == path.isCancelled)
  }

  @Test(
    "앞뒤 통화 표시·금액 끝 표시(也·整·정)·앞 표시(金·금)·전각을 읽고, 앞뒤 통화가 어긋나면 통화 모름이다",
    arguments: [
      ReceiptPath("A83 엔", ["ローソン", "合計 ¥1,100円"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A83 원", ["합계 ₩9,000원"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A83 달러", ["TOTAL $45.20 USD"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A83 어긋남", ["TOTAL ¥1,100원"]),
      ReceiptPath("A83b 앞 달러 뒤 CAD", ["TOTAL $45.20 CAD"]),
      ReceiptPath("A83b 뒤 CAD", ["TOTAL 45.20 CAD"]),
      ReceiptPath("A83b A$", ["TOTAL A$45.20"]),
      ReceiptPath("A84 원정", ["합계 금9,000원정"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A84 円也", ["ローソン", "合計 金1,100円也"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A84 元整", ["超市 元", "合计 88.00元整"], amount: receiptAmount(8800, .cny)),
      ReceiptPath("A84b 붙은 라벨", ["결제금액9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A84b 라벨 아님", ["금액9,000"]),
      ReceiptPath("A84c 정식", ["합계 9,000원정식"]),
      ReceiptPath("A84c 也分", ["ローソン", "合計 1,100円也分"]),
      ReceiptPath("A85 엔", ["ローソン", "合計 ￥１，１００"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("A85 달러", ["TOTAL ＄45.20"], amount: receiptAmount(4520, .usd)),
    ]
  )
  func currencyAndEndMarks(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "△·▲ 는 엔, 负 는 위안일 때만, 통화 표시 뒤 마이너스는 늘 음수이고 부호는 수에 붙어야 한다",
    arguments: [
      ReceiptPath("C109 △", ["ローソン", "返品", "合計 △1,100円"], amount: receiptAmount(1100, .jpy), isCancelled: true),
      ReceiptPath("C109 ▲", ["ローソン", "合計 ▲¥1,100"], amount: receiptAmount(1100, .jpy), isCancelled: true),
      ReceiptPath("C109 △ 공백 ¥", ["ローソン", "合計 △ ¥1,100"], amount: receiptAmount(1100, .jpy), isCancelled: true),
      ReceiptPath("C109 원 ▲", ["합계 ▲1,000"], amount: receiptAmount(1000, .krw)),
      ReceiptPath("C110 ¥-", ["ローソン", "合計 ¥-1,100"], amount: receiptAmount(1100, .jpy), isCancelled: true),
      ReceiptPath("C110 $-", ["TOTAL $-12.50"], amount: receiptAmount(1250, .usd), isCancelled: true),
      ReceiptPath("C110 $ - 공백", ["TOTAL $ - 12.50"], amount: receiptAmount(1250, .usd)),
      ReceiptPath("C110 ¥ - 공백", ["ローソン", "合計 ¥ - 1,100"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("C110 △ 공백 수", ["ローソン", "合計 △ 1,100円"], amount: receiptAmount(1100, .jpy)),
      ReceiptPath("C111 负", ["超市 元", "人民币", "合计 负¥88.00"], amount: receiptAmount(8800, .cny), isCancelled: true),
      ReceiptPath("C8 괄호", ["합계 (9,000)"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("A15 떨어진 줄표", ["합계 - 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func signConventions(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.amount == path.amount)
    #expect(info.isCancelled == path.isCancelled)
  }

  @Test(
    "할인 마이너스가 섞인 합계 줄·별도 할인 줄은 합계를 바꾸지 않고 취소가 아니다(C112)",
    arguments: [
      ReceiptPath("C112 달러", ["Total $45.20 Discount $-5.00"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("C112 원", ["합계 ₩10,000 할인 ₩-1,000"], amount: receiptAmount(10000, .krw)),
      ReceiptPath("C112 엔", ["ローソン", "合計 ¥1,000 値引 △100"], amount: receiptAmount(1000, .jpy)),
      ReceiptPath("C112 별도 줄", ["ローソン", "小計 ¥1,100", "値引 △100", "合計 ¥1,000"], amount: receiptAmount(1000, .jpy)),
    ]
  )
  func discountMinusLines(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.amount == path.amount)
    #expect(!info.isCancelled)
  }
}
