import Core
import Testing

/// 금액을 잘못 고르는 경로(설계 A1~A30)와 막는 규칙. OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
/// 한글이 없는 경로는 통화를 정하도록 금액에 `$` 를 붙인다(표시 없는 영문 영수증은 통화 모름이다).
struct ReceiptExtractorAmountPathTests {
  @Test("같은 높이에 수량 줄과 금액 줄이 따로 있으면 가장 오른쪽 금액을 읽는다")
  func readsRightmostAmountOnSameRow() {
    let path = ReceiptPath("A1", lines: [
      receiptLine("합계", x: 0.1, y: 0.5, width: 0.2),
      receiptLine("3", x: 0.4, y: 0.5, width: 0.05),
      receiptLine("9,000", x: 0.7, y: 0.5, width: 0.15),
    ], amount: receiptAmount(9000, .krw))

    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "같은 높이 금액 줄 오른쪽에 금액 아닌 줄이 있거나, 아래 금액 줄과 같은 높이에 다른 금액이 있으면 금액 모름",
    arguments: [
      ReceiptPath("A2", lines: [
        receiptLine("합계", x: 0.1, y: 0.5, width: 0.2),
        receiptLine("9,000", x: 0.4, y: 0.5, width: 0.15),
        receiptLine("승인 12345678", x: 0.6, y: 0.5, width: 0.3),
      ]),
      ReceiptPath("A12", lines: [
        receiptLine("합계", x: 0.1, y: 0.5, width: 0.2),
        receiptLine("9,000", x: 0.1, y: 0.54, width: 0.15),
        receiptLine("4,500", x: 0.6, y: 0.54, width: 0.15),
      ]),
    ]
  )
  func unreliableColumnsAreUnknown(_ path: ReceiptPath) {
    #expect(path.extracted.amount == nil)
  }

  @Test(
    "라벨 뒤 첫 낱말이 금액·통화가 아니면 라벨 줄이 아니다",
    arguments: [
      ReceiptPath(
        "A3",
        ["TOTAL $45.20", "TOTAL SAVINGS $5.00", "TOTAL NUMBER OF ITEMS SOLD 3", "TOTAL DISCOUNT $2.00"],
        amount: receiptAmount(4520, .usd)
      ),
      ReceiptPath("A4", ["Total Tax $3.20"]),
      ReceiptPath("A5", ["합계 수량 3", "합계 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func otherWordsAfterLabelAreNotLabelLines(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "라벨 줄의 수량·백분율·끊는 말 뒤 금액은 쓰지 않고 마지막 금액을 쓴다",
    arguments: [
      ReceiptPath("A6", ["합계 3개 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A7", ["결제금액 9,000 부가세 818"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A8", ["합계 10% 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A19 날짜", ["합계 2026.10.21 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A19 시각", ["합계 12:30 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func usesLastAmountInRange(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "단계가 높은 라벨이 앞서고, 같은 단계의 값이 다르면 금액 모름, 같으면 그 값",
    arguments: [
      ReceiptPath("A9", ["합계 9,000", "할인 -1,000", "결제금액 8,000"], amount: receiptAmount(8000, .krw)),
      ReceiptPath("A10", ["결제금액 4,500", "결제금액 12,000"]),
      ReceiptPath("A11", ["합계 9,000", "합계 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func choosesHighestStage(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "통화 표시만 남은 라벨 줄은 이웃 금액 줄을 읽고, 점 리더를 건너뛴다",
    arguments: [
      ReceiptPath("A13", lines: [
        receiptLine("Total USD", x: 0.1, y: 0.5, width: 0.3),
        receiptLine("45.20", x: 0.7, y: 0.5, width: 0.15),
      ], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A14", ["TOTAL.......$45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A14 말줄임", ["합계……9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func readsNeighborAndDotLeaders(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "떨어진 줄표는 부호가 아니고, 통화 표시 없는 두 자리 이하 정수는 금액이 아니다",
    arguments: [
      ReceiptPath("A15", ["합계 - 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A16", ["합계 3"]),
    ]
  )
  func separatorDashAndSmallIntegers(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.amount == path.amount)
    #expect(!info.isCancelled)
  }

  @Test(
    "줄 중간 라벨과 라벨 없는 영수증은 가장 큰 숫자를 쓰지 않고 금액 모름",
    arguments: [
      ReceiptPath("A17", ["공급가액 8,182 부가세 818 합계 9,000"]),
      ReceiptPath(
        "A18",
        ["아메리카노 2 9,000", "승인번호 12345678", "010-1234-5678", "000-00-00000", "1234-56**-****-1234"]
      ),
    ]
  )
  func noLeadingLabelIsUnknown(_ path: ReceiptPath) {
    #expect(path.extracted.amount == nil)
  }

  @Test("값이 0 인 취소금액 줄은 금액을 막지 않는다(A20)")
  func zeroCancelAmountDoesNotBlock() {
    let info = extractReceipt(["취소금액 0", "합계 9,000"])
    #expect(info.amount == receiptAmount(9000, .krw))
    #expect(!info.isCancelled)
  }

  @Test(
    "라벨 꼬리 말(금액·金額·amount·due·paid·sale)을 건너뛰고 판정하고, 숫자 없는 괄호 덧말은 판정·범위에서 지운다",
    arguments: [
      ReceiptPath("A21 붙음", ["ローソン", "合計金額 ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A21 띄움", ["ローソン", "合計 金額 ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A22 띄움", ["총합계 금액 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A22 붙음", ["총합계금액 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A23 due", ["TOTAL AMOUNT DUE $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A23 paid", ["TOTAL PAID $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A23 sale", ["TOTAL SALE $45.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A24 税込", ["ローソン", "合計(税込) ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A24 VAT", ["합계(VAT포함) 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A25", ["합계금액 안내", "9,000"]),
      ReceiptPath("A28 전각", ["ローソン", "合計（税込） ¥1,234"], amount: receiptAmount(1234, .jpy)),
      ReceiptPath("A28 원", ["합계(원) 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func skipsTailWordsAndParentheticals(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test(
    "끊는 말은 콜론·등호로 붙어도 범위를 끊는다",
    arguments: [
      ReceiptPath("A29 부가세", ["결제금액 9,000 부가세:818"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A29 VAT", ["결제금액 9,000 VAT:818"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A29 붙음", ["결제금액 9,000 부가세818"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("A30 콜론", ["TOTAL $45.20 TAX:$3.20"], amount: receiptAmount(4520, .usd)),
      ReceiptPath("A30 등호", ["TOTAL $45.20 TAX=3.20"], amount: receiptAmount(4520, .usd)),
    ]
  )
  func cutWordsWithAttachedValues(_ path: ReceiptPath) {
    #expect(path.extracted.amount == path.amount)
  }

  @Test("라벨 뒤에 글자가 붙은 줄은 라벨 줄이 아니다(A26)")
  func attachedLettersAreNotLabels() {
    #expect(extractReceipt(["Totally Fresh $9.99", "TOTAL $9.99"]).amount == receiptAmount(999, .usd))
    #expect(extractReceipt(["Totally Fresh $9.99"]).amount == nil)
  }

  @Test(
    "같은 단계에 서로 다른 금액이 있으면(나눠 낸 결제·이용내역 목록) 금액 모름",
    arguments: [
      ReceiptPath("A10", ["결제금액 4,500", "결제금액 12,000"]),
      ReceiptPath("A27", ["결제금액 5,000", "결제금액 4,000"]),
    ]
  )
  func differingValuesInStageAreUnknown(_ path: ReceiptPath) {
    #expect(path.extracted.amount == nil)
  }
}
