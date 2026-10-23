import Core
import Testing

/// 취소 전표를 잘못 판정하는 경로(설계 C1~C19). OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct ReceiptExtractorCancelTests {
  @Test(
    "값이 있는 취소금액·환불금액 줄은 고른 금액 단계와 상관없이 취소이고, 값이 0 이면 아니다",
    arguments: [
      ReceiptPath("C1", ["합계 9,000", "취소금액 9,000"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("C1 환불", ["환불금액 9,000"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("C11", ["취소금액 0", "반품금액 0", "합계 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("C11 원", ["취소금액 0원", "합계 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func cancelAmountLines(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled == path.isCancelled)
    #expect(info.amount == path.amount)
  }

  @Test(
    "취소 제목 줄·취소 상태 줄·취소 머리말 줄은 취소다",
    arguments: [
      ReceiptPath("C2", ["승인금액 9,000", "[신용승인취소]"]),
      ReceiptPath("C3", ["거래종류 신용취소", "합계 9,000"]),
      ReceiptPath("C4", ["거래구분: 취소"]),
      ReceiptPath("C5", ["*** 취소 매출전표 ***", "합계 9,000"]),
      ReceiptPath("C6", ["결제가 취소되었습니다.", "결제금액 4,500원"]),
      ReceiptPath("C7", ["TYPE: VOID", "TOTAL $9.00"]),
      ReceiptPath("머리말", ["원거래일자 2026-10-01", "합계 9,000"]),
    ]
  )
  func titleStatusAndHeaderLines(_ path: ReceiptPath) {
    #expect(path.extracted.isCancelled)
  }

  @Test(
    "음수 합계는 취소이고 금액은 절댓값이며, 떨어진 줄표는 아니다",
    arguments: [
      ReceiptPath("C8 부호", ["합계 -9,000"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("C8 괄호", ["합계 (9,000)"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("C8 뒤 부호", ["합계 9,000-"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath("C8 달러", ["TOTAL -$9.00"], amount: receiptAmount(900, .usd), isCancelled: true),
      ReceiptPath("C12", ["합계 - 9,000"], amount: receiptAmount(9000, .krw)),
    ]
  )
  func negativeTotals(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled == path.isCancelled)
    #expect(info.amount == path.amount)
  }

  @Test(
    "화면 버튼('취소'·'결제취소'·'주문취소'·'환불')과 안내문 속 취소·환불, 정상 상태는 취소가 아니다",
    arguments: [
      ReceiptPath("C9 결제취소", ["결제금액 4,500원", "결제취소"]),
      ReceiptPath("C9 취소", ["결제금액 4,500원", "취소"]),
      ReceiptPath("C9 주문취소", ["결제금액 4,500원", "주문취소"]),
      ReceiptPath("C9 환불", ["결제금액 4,500원", "환불"]),
      ReceiptPath("C10", ["결제 취소는 구매처에서 가능합니다", "교환/환불은 7일 이내", "합계 9,000"]),
      ReceiptPath("C13", ["상태 결제완료", "합계 9,000"]),
    ]
  )
  func buttonsAndNoticesAreNotCancellations(_ path: ReceiptPath) {
    #expect(!path.extracted.isCancelled)
  }

  @Test(
    "취소 가능·불가·요청·접수 상태는 취소가 아니다",
    arguments: ["주문상태 결제완료(취소가능)", "상태 취소불가", "결제상태 취소 요청 가능", "처리상태 취소접수"]
  )
  func pendingCancelStatesAreNotCancellations(_ status: String) {
    let info = extractReceipt([status, "결제금액 9,000원"])
    #expect(!info.isCancelled)
    #expect(info.amount == receiptAmount(9000, .krw))
  }

  @Test(
    "VOID·취소완료 같은 상태 문구는 첫 금액 위에 있을 때만 취소이고, 전표 이름은 위치와 상관없이 취소다",
    arguments: [
      ReceiptPath(
        "C15",
        ["EXAMPLE FOODS", "BANANAS $1.99", "** VOID **", "BANANAS -$1.99", "MILK $3.49", "TOTAL $3.49"],
        amount: receiptAmount(349, .usd),
        storeName: "EXAMPLE FOODS"
      ),
      ReceiptPath(
        "C16",
        ["VOID", "EXAMPLE FOODS", "MILK $3.49", "TOTAL $3.49"],
        amount: receiptAmount(349, .usd),
        storeName: "EXAMPLE FOODS",
        isCancelled: true
      ),
      ReceiptPath("C17", ["아메리카노 4,500", "취소완료", "합계 4,500"], amount: receiptAmount(4500, .krw)),
      ReceiptPath("C18", ["합계 9,000", "취소영수증"], amount: receiptAmount(9000, .krw), isCancelled: true),
    ]
  )
  func statusPhrasesOnlyAboveFirstAmount(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled == path.isCancelled)
    #expect(info.amount == path.amount)
    // 위 VOID 같은 상태 문구 줄은 가게가 아니다(C15·C16). C17·C18 은 첫 줄이 본문 줄이라 가게 모름이다.
    #expect(info.storeName == path.storeName)
  }

  @Test("상태 라벨은 뒤 경계가 있을 때만 라벨이고 값에 정책·안내 말이 있으면 근거가 아니다(C19)")
  func statusLabelNeedsBoundary() {
    let info = extractReceipt(["Typewriter Cafe", "TOTAL $9.00", "type: refund policy"])
    #expect(!info.isCancelled)
    #expect(info.amount == receiptAmount(900, .usd))
  }

  @Test(
    "한글·한자·가나 3자 이상 상태 라벨과 취소 머리말은 붙은 값도 받고, 일본어·중국어 전표 이름도 취소다",
    arguments: [
      ReceiptPath("C20", ["거래구분신용취소", "합계 9,000"]),
      ReceiptPath("C21", ["ローソン", "取引区分 取消", "合計 ¥1,100"]),
      ReceiptPath("C22", ["取消レシート", "合計 ¥1,100"]),
      ReceiptPath("C26", ["취소일시2026-10-21 12:30", "합계 9,000"]),
      ReceiptPath("C29", ["ローソン", "取引区分取消", "合計 ¥1,100"]),
    ]
  )
  func attachedCJKStatusLabels(_ path: ReceiptPath) {
    #expect(path.extracted.isCancelled)
  }

  @Test(
    "2자 상태 라벨은 뒤 경계가 필요하고, 대기·조건 낱말이나 10자를 넘는 값, 단독 取消 버튼, 라틴 붙은 글자는 근거가 아니다",
    arguments: [
      ReceiptPath("C23", ["状態 取消可能", "合計 ¥1,100"]),
      ReceiptPath("C24", ["取消", "合計 ¥1,100"]),
      ReceiptPath("C25", ["Typewriter refund desk", "TOTAL 9.00"]),
      ReceiptPath("C27", ["상태불량시 환불", "합계 9,000"]),
      ReceiptPath("C28", ["상태 불량시 환불", "합계 9,000"]),
      ReceiptPath("C30", ["거래구분 취소(고객 요청으로 처리된 거래입니다)", "합계 9,000"]),
    ]
  )
  func boundedOrPendingStatusIsNotCancellation(_ path: ReceiptPath) {
    #expect(!path.extracted.isCancelled)
  }
}
