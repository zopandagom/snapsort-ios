import Core
import Testing

/// 진행·요청·대기·거절·부정 꼴의 상태 값을 취소로 보는 경로(설계 r3.13·r3.14, C63~C78). OCR 줄은 지어낸 텍스트다
/// (docs/CONVENTIONS.md §3).
struct ReceiptExtractorPendingTests {
  /// 상태 줄을 그 언어의 합계 줄과 함께 둔다.
  private static func receipt(_ status: String) -> [String] {
    if status.contains(where: \.isHangulSyllable) {
      return [status, "합계 9,000"]
    }
    if status.unicodeScalars.contains(where: { (0x3040 ... 0x30FF).contains($0.value) }) || status.contains("状態") {
      return ["ローソン", status, "合計 ¥1,100"]
    }
    if status.unicodeScalars.contains(where: { (0x4E00 ... 0x9FFF).contains($0.value) }) {
      return [status, "合计 ¥88.00", "人民币"]
    }
    return [status, "TOTAL 12.50"]
  }

  @Test(
    "진행·요청·대기·거절 말이나 취소 말 앞의 부정 말이 든 상태 값은 취소가 아니다",
    arguments: [
      "Status: Refund requested", "Status: Refund pending", "Status: Refund processing", "Status: Cancellation pending",
      "Status: Return initiated", "Status: Return in progress", "Status: Refund denied", "Status: Not cancelled",
      "Status: No refund",
      "Status: Cancel requested", "결제상태: 환불진행중", "처리상태: 반품처리중", "상태: 환불없음", "상태: 취소안됨", "상태: 미취소", "状态 退款中",
      "状态 退款处理中", "状態 返金待ち", "状態 未返金", "状态 退款失败", "Vorgang: Storno abgelehnt", "Type: Remboursement en attente",
      "Tipo: Reembolso pendiente", "Tipo: Rimborso in attesa", "Type: Annulation refusée", "Vorgang: Nicht storniert",
      "状態 中止",
    ]
  )
  func pendingOrNegatedStatusIsNotCancellation(_ status: String) {
    #expect(!extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "완료형 상태 값과 끝이 아닌 한 글자 대기 말은 취소다",
    arguments: [
      "Status: Refunded", "Status: Cancelled", "결제상태: 취소완료", "状态 退款成功", "状态 已退款", "Status: Partially refunded",
      "Vorgang: Storniert", "Status: Voided Transaction", "Status: Cancelled in store",
      "상태: 환불(중복결제)",
      "状态 退款成功 处理时间", "결제상태: 취소완료 시각", "상태: 이미 환불처리", "상태: 취소후재결제", "Status: Refund Process Complete",
    ]
  )
  func completedStatusIsCancellation(_ status: String) {
    #expect(extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "부정·대기·미완료 말은 취소 말 뒤에 와도, 되돌린 환불도 취소가 아니다(r3.16·r3.17)",
    arguments: [
      // C79·C80: 라틴 부정·대기(같은 구절, 앞뒤)
      "Status: Refund not issued", "Status: Refund not processed", "Status: Return not accepted",
      "Status: Refund on hold",
      "Status: Refund withdrawn", "Vorgang: Storno nicht erfolgt", "Type: Remboursement non effectué",
      "Tipo: Reembolso no realizado",
      "Tipo: Devolución no realizada", "Tipo: Rimborso non effettuato",
      // C82·C83: 미·未·没 는 취소 말·완료·처리 꼴 바로 앞, 철회·关闭 류는 취소 말 바로 뒤
      "상태: 환불 미처리", "상태: 취소 미완료", "상태: 반품미승인", "상태: 취소철회", "상태: 환불반려", "상태: 미취소", "状态 退款未成功",
      "状态 退款未完成", "状态 退款不成功", "状态 退款关闭", "状態 返金未完了", "状態 返金未処理", "状態 キャンセル未処理", "状態 返金却下",
      "状态 没退款",
      // C86: 不·无 는 취소 말 바로 앞이나 부정 꼴
      "状态 不退款", "状态 无法退款", "状态 无退款", "状态 待退款",
      // C90: 되돌린 환불
      "Status: Refund reversed", "Type: Return reversal",
    ]
  )
  func trailingNegationAndReversalAreNotCancellation(_ status: String) {
    #expect(!extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "번호 표시 no, 다른 구절의 부정, 不良·无理由, 다른 대상의 미·关闭 는 취소를 막지 않는다(r3.16·r3.17)",
    arguments: [
      // C81: 번호 표시(C72 에서 옮김)
      "Status: Refund No. 1234", "Status: Refund Nr. 55", "Status: Refund no 1234",
      // C84 회귀
      "상태: 이미 환불처리", "状態 取消済み", "状态 退款成功", "状态 已退款", "Status: Refund issued",
      // C85·C87
      "状態 不良品返品", "状态 不良退货", "状态 无理由退货",
      // C90 회귀
      "Status: Transaction reversed", "Status: Reversed",
      // C91: 다른 구절의 부정
      "Status: Cancelled - no charge", "Status: Void - not valid", "Vorgang: Storniert, keine Gebühr",
      // C92: 未·미 뒤가 취소·완료 꼴이 아님
      "状态 已退款 未使用", "状態 取消済み 未使用", "상태: 미사용분 환불완료",
      // C94: 关闭 가 취소 말 바로 뒤가 아님
      "状态 退款成功 交易关闭", "状态 订单已关闭 已退款",
    ]
  )
  func otherPhraseNegationIsCancellation(_ status: String) {
    #expect(extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "환불 금액 뒤에 대기·부정 말이 있으면 취소 근거도 금액 후보도 아니다(C88·C89·C93)",
    arguments: [
      ReceiptPath("C88 pending", ["Refund amount $12.00 pending", "TOTAL $12.00"], amount: receiptAmount(1200, .usd)),
      ReceiptPath("C88 미처리", ["환불금액 9,000 미처리", "합계 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("C88 处理中", ["退款金额 ¥88.00 处理中", "合计 ¥88.00", "人民币"], amount: receiptAmount(8800, .cny)),
      ReceiptPath(
        "C89",
        ["Refund amount $12.00", "TOTAL $12.00"],
        amount: receiptAmount(1200, .usd),
        isCancelled: true
      ),
      ReceiptPath("C89 退款", ["退款金额 ¥88.00", "合计 ¥88.00", "人民币"], amount: receiptAmount(8800, .cny), isCancelled: true),
      ReceiptPath(
        "C93",
        ["ローソン", "返金額 ¥1,100 (未使用分)", "合計 ¥1,100"],
        amount: receiptAmount(1100, .jpy),
        isCancelled: true
      ),
      ReceiptPath("C93 미사용분", ["환불금액 9,000 (미사용분)", "합계 9,000"], amount: receiptAmount(9000, .krw), isCancelled: true),
      ReceiptPath(
        "C99",
        ["退款金额 ¥88.00 已退款 未到账", "合计 ¥88.00", "人民币"],
        amount: receiptAmount(8800, .cny),
        isCancelled: true
      ),
    ]
  )
  func pendingRefundAmountLine(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled == path.isCancelled)
    #expect(info.amount == path.amount)
  }

  @Test(
    "待 는 어디서든, 未·没·미 는 처리·확인 꼴 앞이면, 라틴 대기 말은 값 어디서든 취소가 아니다(r3.18·r3.19)",
    arguments: [
      // C95·C100: 待
      "状态 退款待处理", "状态 退款待确认", "状态 退款待到账", "状态 退款待审核", "状态 待退款", "状態 返金待ち", "状态 退款待商家处理",
      "状态 待买家退货", "状态 退款等待处理",
      // C96: 라틴 대기·거절은 다른 구절이어도
      "Status: Refund - Pending", "Status: Refund, pending", "Status: Refund / denied", "Status: Return / Requested",
      "Status: Refunded - pending review",
      // C97: 반영·확인·済 꼴
      "상태: 취소미반영", "상태: 환불미확인", "状態 返金未済", "状態 返金未確認",
      // 완료와 처리 미완료가 어긋난 값(판단하지 않음)
      "状态 退款成功 未处理",
    ]
  )
  func waitingAndNotYetAreNotCancellation(_ status: String) {
    #expect(!extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "완료 표시가 있으면 돈의 도착·정산이 아직이어도 취소다(C98·C101)",
    arguments: ["状态 退款成功 未到账", "状态 已退款 未到账", "상태: 취소완료 미반영", "状態 返金完了 未入金", "状态 退款成功 待到账"]
  )
  func settledArrivalPendingIsCancellation(_ status: String) {
    #expect(extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "환불·반품 말 뒤에 취소 말이 오면 환불을 되돌린 것이라 취소가 아니다(C102~C104)",
    arguments: [
      "상태: 반품취소", "상태: 환불취소", "상태: 환불취소완료", "상태: 환불 취소", "상태: 환불을 취소", "Status: Refund cancelled",
      "Status: Return cancelled", "Status: Refund voided", "Vorgang: Erstattung storniert",
      "Type: Remboursement annulé",
      "Tipo: Reembolso anulado", "Tipo: Rimborso annullato", "状态 退款已撤销", "状态 退款撤销", "状态 退货已取消", "状態 返品キャンセル",
      "状態 返金取消", "상태: 재결제후환불",
    ]
  )
  func reversedRefundIsNotCancellation(_ status: String) {
    #expect(!extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "순서가 반대(취소한 뒤 환불)이거나 撤销 단독이면 취소다(C105·C107)",
    arguments: [
      "상태: 취소환불", "Status: Cancelled - refund issued", "状态 订单已取消 已退款", "状态 交易已撤销", "Status: Refund issued",
      "상태: 취소후환불", "상태: 취소후재결제",
    ]
  )
  func cancelThenRefundIsCancellation(_ status: String) {
    #expect(extractReceipt(Self.receipt(status)).isCancelled)
  }

  @Test(
    "환불 금액 뒤에 취소 말이 있으면 되돌린 환불이라 근거도 후보도 아니고, 취소금액 줄은 그대로 근거다(C106)",
    arguments: [
      ReceiptPath("C106 환불", ["환불금액 9,000 취소", "합계 9,000"], amount: receiptAmount(9000, .krw)),
      ReceiptPath("C106 refund", ["Refund amount $12.00 cancelled", "TOTAL $12.00"], amount: receiptAmount(1200, .usd)),
      ReceiptPath("C106 회귀 취소금액", ["취소금액 9,000", "합계 9,000"], amount: receiptAmount(9000, .krw), isCancelled: true),
    ]
  )
  func reversedRefundAmountLine(_ path: ReceiptPath) {
    let info = path.extracted
    #expect(info.isCancelled == path.isCancelled)
    #expect(info.amount == path.amount)
  }

  @Test("단독 refunded 는 단계 3 라벨이 아니라 병 보증금 환불 줄이 영수증을 취소로 만들지 않는다(C63)")
  func refundedDepositLineIsNotCancellation() {
    let info = extractReceipt(["REFUNDED $0.25 BOTTLE", "TOTAL $12.50"])
    #expect(!info.isCancelled)
    #expect(info.amount == receiptAmount(1250, .usd))
  }
}

private extension Character {
  var isHangulSyllable: Bool {
    self.unicodeScalars.allSatisfy { (0xAC00 ... 0xD7A3).contains($0.value) }
  }
}
