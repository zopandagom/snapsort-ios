import Core
import Testing

/// 금액 토큰 문법(설계 §2.5). `TOTAL <토큰>` 줄 하나와 통화를 정하는 문맥 줄로 읽는다. OCR 줄은 지어낸 텍스트다.
struct ReceiptExtractorAmountTests {
  struct TokenCase: Sendable, CustomTestStringConvertible {
    let text: String
    /// 통화를 정하는 다른 줄(한글 영수증·가나·통화 코드).
    let context: String
    let expected: ReceiptAmount?

    init(_ text: String, context: String, _ expected: ReceiptAmount?) {
      self.text = text
      self.context = context
      self.expected = expected
    }

    var testDescription: String { self.text }
  }

  @Test(
    "천 단위 구분·소수 형식을 통화 자릿수로 읽는다",
    arguments: [
      TokenCase("9,000", context: "예시마트", receiptAmount(9000, .krw)),
      TokenCase("1,234,567", context: "예시마트", receiptAmount(1_234_567, .krw)),
      TokenCase("45.20", context: "USD", receiptAmount(4520, .usd)),
      TokenCase("45.2", context: "USD", receiptAmount(4520, .usd)),
      TokenCase("1.234,56 €", context: "EXAMPLE", receiptAmount(123_456, .eur)),
      TokenCase("12,50 €", context: "EXAMPLE", receiptAmount(1250, .eur)),
      TokenCase("1.234 €", context: "EXAMPLE", receiptAmount(123_400, .eur)),
      TokenCase("9,000.00원", context: "예시마트", receiptAmount(9000, .krw)),
      TokenCase("₩9,000", context: "EXAMPLE", receiptAmount(9000, .krw)),
      TokenCase("9,000 원", context: "예시마트", receiptAmount(9000, .krw)),
      TokenCase("¥1,234", context: "ローソン", receiptAmount(1234, .jpy)),
      TokenCase("US$45.20", context: "EXAMPLE", receiptAmount(4520, .usd)),
      TokenCase("₩1,000,000,000,000", context: "EXAMPLE", receiptAmount(ReceiptAmount.maximumMinorUnits, .krw)),
    ]
  )
  func readsNumberFormats(_ token: TokenCase) {
    #expect(extractReceipt([token.context, "TOTAL \(token.text)"]).amount == token.expected)
  }

  @Test(
    "통화 자릿수를 넘는 0 아닌 소수, 잘못된 천 단위, 8자리 이상 정수, 상한 초과는 금액이 아니다",
    arguments: [
      TokenCase("9,000.50원", context: "예시마트", nil),
      TokenCase("¥1,234.5", context: "ローソン", nil),
      // 점 천 단위(b)는 유로에서만 금액이다. 다른 통화면 "$45.205" 같은 오독을 큰 금액으로 읽지 않는다.
      TokenCase("$45.205", context: "EXAMPLE", nil),
      TokenCase("$1.234", context: "EXAMPLE", nil),
      TokenCase("1.234원", context: "예시마트", nil),
      TokenCase("1,23,456", context: "예시마트", nil),
      TokenCase("12345678", context: "예시마트", nil),
      TokenCase("₩1,000,000,000,001", context: "EXAMPLE", nil),
    ]
  )
  func rejectsInvalidNumbers(_ token: TokenCase) {
    #expect(extractReceipt([token.context, "TOTAL \(token.text)"]).amount == nil)
  }
}
