import Foundation

// 영수증 추출의 낱말 표 (docs/ARCHITECTURE.md §4 영수증 추출). 표마다 대조 방식이 다르다(각 표 주석).
// 한글·한자·가나로 된 말과 라틴 글자 말을 한 표에 두고, 대조하는 쪽이 문자 체계로 방식을 나눈다(`isCJK`).
extension ReceiptExtractor {
  // MARK: - 금액

  /// 금액 라벨. 단계 1(최종 결제) → 2(합계) → 3(취소 전표, 취소 판정에 쓰고 1·2 값이 없을 때만 금액). 공백 없이 소문자로 적는다.
  static let amountLabels: [Int: [String]] = [
    1: [
      "결제금액", "총결제금액", "최종결제금액", "실결제금액", "결제하실금액", "승인금액", "받을금액", "청구금액", "grandtotal", "totaldue",
      "amountdue", "totalamountdue", "totalamount", "totalpaid", "お会計", "ご請求額", "お支払金額", "お支払い金額", "お支払合計",
      "ご利用金額", "ご利用額", "应付金额", "实付金额", "实付", "支付金额", "应收金额", "お支払", "お支払い", "ご請求", "お会計金額",
      "ご請求金額",
    ],
    2: [
      "합계금액", "합계액", "총합계금액", "총합계", "총금액", "총액", "합계", "total", "合計金額", "税込合計", "合計税込", "合計", "合计",
      "合计金额", "総合計", "総合計金額", "総額", "总计", "总金额", "总额",
    ],
    // 단계 3 은 금액이 붙는 복합 라벨만 둔다. 단독 환불 낱말(refunded·gutschrift·erstattung·rimborso 등)은 정상 영수증의 보증금·크레딧 줄에도
    // 금액과 함께 와서 넣지 않는다. 단독 "退款"·"refund" 는 버튼일 수 있어 넣지 않는다.
    3: [
      "취소금액", "환불금액", "반품금액", "返金額", "返金金額", "ご返金額", "取消金額", "返品金額", "退款金额", "退款额", "退货金额",
      "refundamount", "refundtotal", "totalrefund", "amountrefunded", "erstattungsbetrag",
      "rückerstattungsbetrag",
      "stornobetrag", "montantrembourse", "montantremboursé", "importedevuelto", "importorimborsato",
    ],
  ]
  static let allAmountLabels = amountLabels.values.flatMap(\.self)
  /// 라벨 바로 뒤에서 건너뛰는 꼬리 말(낱말 같음): "合計 金額 ¥1,234", "TOTAL AMOUNT DUE 45.20", "合計 税込 ¥1,234".
  static let labelTailWords: Set<String> = [
    "금액", "액", "金額", "金额", "額", "税込", "amount", "due", "payable", "paid", "sale",
  ]
  /// 통화 표시 낱말(낱말 같음). 지원하지 않는 통화 코드도 통화 표시로 센다(라벨 줄 판정·첫 금액 묶음에서 글자 낱말이 아니다).
  static let currencyWords: Set<String> = [
    "krw", "usd", "eur", "jpy", "cny", "rmb", "원", "円", "元", "won", "cad", "aud", "gbp", "hkd", "sgd", "twd", "nzd",
    "mxn",
    "chf",
    "thb", "vnd", "php", "inr",
  ]
  /// 지원하지 않는 통화 코드(ISO 4217). 토큰의 앞·뒤 표시와 줄의 통화 표시에서 통화 모름으로 센다.
  static let unsupportedCurrencyCodes = [
    "CAD", "AUD", "GBP", "HKD", "SGD", "TWD", "NZD", "MXN", "CHF", "THB", "VND", "PHP", "INR",
  ]
  /// 지원하지 않는 통화 기호.
  static let unsupportedCurrencySymbols: [Character] = ["£", "₹", "₱", "฿", "₫"]
  /// 금액 값 범위를 끊는 말. 한글·한자·가나는 값 범위 어디서나 부분 문자열로, 라틴 글자는 낱말 같음(또는 바로 뒤가 숫자·`:`·`：`·
  /// `=`·통화 기호)으로 찾는다(`cutPosition`). "税" 는 "税込"(세금 포함 합계)를 끊으므로 넣지 않는다.
  static let cutWords = [
    "부가세", "부가가치세", "공급가액", "공급가", "과세", "면세", "비과세", "할인", "받은금액", "받은돈", "거스름", "잔돈", "승인번호", "카드번호",
    "포인트", "적립", "잔액", "수량", "봉사료", "서비스료", "subtotal", "tax", "taxes", "vat", "change", "cash", "tip", "tips", "qty",
    "savings", "discount", "discounts", "charges", "taxable", "nontaxable", "non-taxable", "お預り", "お預かり", "お預", "お釣り",
    "お釣", "釣銭", "小計", "消費税", "内税", "外税", "税額", "税率", "税抜", "課税", "非課税", "値引", "割引", "ポイント", "対象", "小计",
    "税额", "增值税", "找零", "优惠", "折扣", "实收", "积分",
  ]
  /// 첫 금액과 다음 금액 사이에 오면 할인 뒤 금액이라 그 줄의 값을 쓰지 않는 말. 한글·한자 글자는 어디든(붙어 있어도),
  /// 라틴은 낱말 같음.
  static let afterDiscountCharacters: Set<Character> = ["후", "後", "后"]
  static let afterDiscountLatin: Set<String> = ["after", "net"]
  /// 라벨 바로 뒤 덧말이나 첫 낱말이면 세금 별도 금액이라 라벨 줄이 아니다. 한글·한자는 부분 문자열, 라틴은 낱말 같음(두 낱말 말은
  /// 이어진 두 낱말을 붙여 대조: "sans tva" = sanstva).
  static let taxExcludedWords: Set<String> = [
    "税抜", "税別", "外税", "별도", "공급가", "공급가액", "세전", "부가세제외", "vat별도", "本体", "不含税", "未税", "税前", "excl", "excluding",
    "pretax", "beforetax", "ht", "horstaxe", "netto", "ohnemwst", "exkl", "sanstva", "siniva", "senzaiva",
  ]

  // MARK: - 취소

  /// 취소 전표 이름(줄 같음, 위치 무관). 단독 "取消"·"返品"·"退款" 은 버튼일 수 있어 넣지 않는다.
  static let cancelTitles: Set<String> = [
    "승인취소", "취소승인", "신용취소", "신용승인취소", "카드승인취소", "승인취소전표", "취소전표", "취소영수증", "취소매출전표", "매출전표취소",
    "매출취소", "매출취소전표", "거래취소", "거래취소전표", "현금영수증취소", "현금취소", "취소거래", "반품영수증", "환불영수증", "refundreceipt",
    "取消レシート", "返品レシート", "返金レシート", "取引取消", "返品伝票", "退款单", "退货单", "stornobeleg", "stornierung",
    "gutschriftbeleg", "ticketdannulation", "ticketderemboursement", "ticketdedevolucion", "ticketdedevolución",
    "notadecredito",
    "notadicredito", "scontrinodireso", "returnreceipt", "refundslip", "退款凭证",
  ]
  /// 취소 상태 문구(줄 같음, 첫 금액 줄보다 위에서만).
  static let cancelStatusPhrases: Set<String> = [
    "취소완료", "결제취소완료", "주문취소완료", "환불완료", "반품완료", "결제가취소되었습니다", "취소되었습니다", "환불되었습니다",
    "결제취소되었습니다", "void", "voided", "refunded", "cancelled", "canceled", "cancellation", "取消済み", "取消済", "キャンセル済み",
    "返金済み", "返品済み", "已取消", "已退款", "storno", "storniert", "annulation", "annulé", "annule", "remboursé", "rembourse",
    "anulado", "anulación", "anulacion", "devuelto", "annullato", "rimborsato",
  ]
  /// 취소 상태 라벨(줄 라벨). 3자 이상 한글·한자·가나 라벨은 붙은 값도 받고, 2자와 라틴 라벨은 뒤 경계가 필요하다.
  /// 값(10자 이하)에 `cancelValueWords` 가 있고 `pendingCancelWords` 가 없으면 취소다.
  static let cancelStatusLabels = [
    "거래종류", "거래구분", "거래유형", "결제구분", "결제상태", "거래상태", "주문상태", "처리상태", "구분", "상태", "transactiontype", "type",
    "status", "取引区分", "区分", "状態", "ステータス", "交易类型", "状态", "vorgang", "belegart", "buchungsart", "tipo",
    "typedetransaction", "tipodeoperacion",
  ]
  /// 붙은 값도 받는 상태 라벨(3자 이상 한글·한자·가나). 나머지(2자·라틴)는 뒤 경계가 필요하다.
  static let attachedCancelStatusLabels = cancelStatusLabels.filter { isCJK($0) && $0.count >= 3 }
  static let boundedCancelStatusLabels = cancelStatusLabels.filter { !(isCJK($0) && $0.count >= 3) }
  /// 상태 값의 취소 낱말. 한글·한자·가나 값은 부분 문자열(공백 없이 10자 이하 값만), 라틴 값은 3낱말 이하에서 낱말 같음.
  static let cancelValueWords = ["취소", "환불", "반품", "取消", "返品", "返金", "キャンセル", "退款", "退货", "撤销"]
  static let latinCancelValueWords: Set<String> = [
    "void", "voided", "refund", "refunded", "return", "returned", "cancel", "cancelled", "canceled", "cancellation",
    "storno",
    "storniert", "stornierung", "stornobeleg", "reversal", "reversed", "annule", "annulé", "annulation", "rembourse",
    "remboursé",
    "remboursement", "devolucion", "devolución", "devuelto", "reembolso", "anulado", "anulacion", "anulación",
    "rimborso",
    "rimborsato",
    "annullato", "reso",
  ]
  /// 상태 값에 있으면 아직 취소된 것이 아니다(대기·진행·요청·거절·부정). 한글·한자·가나는 부분 문자열(두 글자 이상).
  static let pendingCancelWords = [
    "가능", "불가", "신청", "요청", "접수", "안내", "정책", "방법", "기한", "수수료", "경우", "진행", "대기", "예정", "보류", "없음", "안됨", "않음",
    "실패", "거절", "거부", "可能", "不可", "申請", "受付", "案内", "可申请", "場合", "待ち", "予定", "失敗", "拒否", "なし", "無し", "ない", "ません",
    "不成立", "申请", "审核", "失败", "拒绝", "驳回", "没有",
  ]
  /// 한 글자 대기 낱말은 자리를 본다(공백 없는 값 기준, `isPendingCJK`).
  /// 중·中: 값 끝("환불진행중"·"退款中". "중복결제"·"中止" 는 아니다).
  static let pendingCancelSuffixes: Set<Character> = ["시", "時", "时", "후", "중", "中"]
  /// 시·時·时·후: 값 끝이거나 취소 낱말 바로 앞("불량시환불". "취소완료시각"·"취소후재결제" 는 아니다).
  static let pendingCancelConditions: Set<Character> = ["시", "時", "时", "후"]
  /// 미·未·没: 바로 뒤가 취소 낱말이나 완료·처리 꼴일 때("환불미처리"·"退款未成功"·"没退款". "이미"·"未使用" 은 아니다).
  static let pendingNotYetMarkers: Set<Character> = ["미", "未", "没"]
  static let completionWords = [
    "완료", "처리", "승인", "진행", "확정", "결제", "접수", "반영", "확인", "입금", "完了", "処理", "承認", "成立", "確定", "処理済", "済", "確認",
    "入金", "着金", "成功", "完成", "处理", "到账", "确认", "通过", "受理", "审核",
  ]
  /// 돈의 도착·정산 꼴. 未·没·미·待 가 이 꼴 앞에 와도 같은 값에 완료 표시가 있으면 대기가 아니다("退款成功 未到账"·"취소완료 미반영").
  static let arrivalWords = ["到账", "入金", "着金", "입금", "반영"]
  /// 완료 표시(앞에 未·没·미·待 가 붙지 않은 것).
  static let completedMarkers = ["완료", "됨", "되었습니다", "済", "済み", "完了", "成功", "已退款", "已取消", "已退货", "退款完成", "完成"]
  /// 待: 값 어디서든 대기다("退款待处理"·"待买家退货"). 이 복합어의 待 는 아니다.
  static let waitingMarker: Character = "待"
  static let waitingExceptions = ["期待", "招待", "待遇", "接待", "優待"]
  /// 不·无: 취소 낱말 바로 앞이거나 부정 꼴의 첫 글자일 때("不退款"·"退款不成功"·"无法退款". "不良品返品"·"无理由退货" 는 취소다).
  static let pendingNegationMarkers: Set<Character> = ["不", "无"]
  static let negationForms = ["不成功", "不可", "不能", "不予", "不通过", "不受理", "不承認", "不成立", "无法", "无效"]
  /// 취소 낱말 바로 뒤에 붙을 때만 대기인 말("취소철회"·"退款关闭". "交易关闭" 는 아니다).
  static let pendingAfterCancelWords = ["철회", "반려", "却下", "撤回", "撤销", "保留", "关闭"]
  /// 라틴 상태 값의 대기·진행·요청·거절 낱말(낱말 같음, 값 어디서든 근거를 막는다).
  static let latinPendingCancelWords: Set<String> = [
    "possible", "available", "eligible", "request", "policy", "requested", "requesting", "pending", "initiated",
    "processing",
    "progress",
    "started", "submitted", "awaiting", "waiting", "scheduled", "review", "reviewing", "open", "denied", "rejected",
    "declined",
    "failed", "refused", "unsuccessful", "error", "allowed", "beantragt", "ausstehend", "offen", "bearbeitung",
    "abgelehnt",
    "fehlgeschlagen", "möglich", "demandé", "demandée", "demande", "attente", "cours", "refusé", "refusée", "rejeté",
    "échoué",
    "solicitado", "solicitud", "pendiente", "proceso", "curso", "rechazado", "denegado", "fallido", "posible",
    "richiesto",
    "richiesta", "attesa", "corso", "rifiutato", "respinto", "fallito", "possibile", "hold", "onhold", "withdrawn",
    "withdraw",
    "incomplete", "unprocessed", "uncompleted", "revoked", "erfolglos",
  ]
  /// 되돌림: 환불·반품 낱말 뒤에 취소 낱말이 오면 환불·반품을 되돌린 것이라 근거가 아니다("반품취소"·"Refund cancelled"·
  /// "退款已撤销"). 순서가 반대면("취소환불"·"Cancelled - refund issued") 진짜 취소다. 상태 문구·전표 이름 표에는 이 꼴을 넣지 않는다.
  /// 한글·한자·가나는 바로 뒤(연결 글자 하나는 있어도 된다), 라틴은 같은 구절 안 뒤 어디든.
  static let refundWordsCJK = ["환불", "반품", "退款", "退货", "返金", "返品"]
  static let reversingCancelWordsCJK = ["취소", "キャンセル", "取消", "撤销", "撤回", "철회"]
  static let reversalConnectors: Set<Character> = ["已", "被", "を", "が", "을", "를", "이", "가"]
  static let refundWords: Set<String> = [
    "refund", "refunded", "return", "returned", "erstattung", "rückerstattung", "remboursement", "reembolso",
    "devolución",
    "devolucion",
    "rimborso", "reso",
  ]
  static let reversingCancelWords: Set<String> = [
    "cancel", "cancelled", "canceled", "cancellation", "void", "voided", "reversed", "reversal", "storniert", "storno",
    "annulé", "annule",
    "annulation", "anulado", "anulación", "anulacion", "annullato",
  ]
  /// 환불·반품 금액 라벨(단계 3 중 취소금액 류 밖). 값 뒤에 취소 낱말이 있으면 환불을 되돌린 줄이다("환불금액 9,000 취소").
  static let refundAmountLabels: Set<String> = [
    "환불금액", "반품금액", "返金額", "返金金額", "ご返金額", "返品金額", "退款金额", "退款额", "退货金额", "refundamount", "refundtotal",
    "totalrefund", "amountrefunded", "erstattungsbetrag", "rückerstattungsbetrag", "montantrembourse",
    "montantremboursé",
    "importedevuelto", "importorimborsato",
  ]
  /// 라틴 부정 낱말(낱말 같음). 취소 낱말과 같은 구절이면 앞뒤 어디서든 근거를 막는다("Not cancelled"·"Refund not issued").
  /// no·nr·n° 가 "." 으로 끝나거나 다음 낱말이 숫자면 번호 표시라 부정이 아니다("Refund No. 1234").
  static let latinNegationWords: Set<String> = [
    "no", "not", "non", "none", "never", "without", "nicht", "kein", "keine", "pas", "aucun", "aucune", "sans", "sin",
    "nessun",
    "senza",
  ]
  /// 한글·한자·가나 상태 값으로 보는 최대 길이(공백 없이). 더 길면 안내문이다.
  static let maximumCancelValueLength = 10
  /// 라틴 상태 값으로 보는 최대 낱말 수.
  static let maximumLatinCancelValueWords = 3
  /// 값과 무관하게 취소 근거인 머리말(줄 라벨, 붙은 값도 받는다). 이름이 번호·일시라 안내문에 오지 않는다.
  static let cancelHeaderLabels = [
    "취소일시", "취소일자", "취소승인번호", "원거래일자", "원승인번호", "원거래승인번호", "取消日時", "返品日時", "元取引番号", "元レシート番号",
    "退款时间", "原单号", "原交易号",
  ]
  /// 라틴 취소 머리말. 안내문("ORIGINAL RECEIPT REQUIRED FOR RETURNS")에도 쓰여, 뒤 경계가 있고 값이 번호·날짜일 때만 근거다.
  static let latinCancelHeaderLabels = ["originalreceipt", "originaltransaction", "origtrans"]
  /// 라틴 머리말 뒤에서 하나 건너뛰는 번호 표시 낱말(낱말 같음): "Original Receipt No. 1234", "Orig Trans Date: 10/01/2026".
  static let numberMarkerWords: Set<String> = ["no", "nr", "n°", "number", "num", "id", "date", "dt"]

  // MARK: - 가게

  /// 1차 가게 라벨(긴 라벨). 줄 라벨이되 공백 없이 붙은 값도 받는다("가맹점명스타벅스", "店名ローソン").
  static let storeLabels = [
    "가맹점명", "상호명", "매장명", "점포명", "가게명", "판매자명", "판매처명", "가맹점이름", "merchantname", "storename", "店舗名", "店名",
    "商户名称", "商户名", "店铺名称",
  ]
  /// 2차 가게 라벨(짧은 라벨). 1차에서 못 찾았을 때만, 라벨 뒤 경계가 있을 때만("상호저축은행" 은 아니다).
  static let shortStoreLabels = ["가맹점", "상호", "판매자", "판매처"]
  /// 라벨 뒤 값의 첫 낱말이 이것과 같으면(낱말 같음) 가게 라벨 줄이 아니다("[가맹점 정보]", "상호 및 대표자").
  static let notStoreValueWords: Set<String> = [
    "번호", "주소", "전화", "전화번호", "코드", "정보", "안내", "내역", "사본", "용", "고객용", "가맹점용", "고객", "문의", "대표", "대표자",
    "사업자", "사업자번호", "등록번호", "및", "copy", "receipt", "info", "information", "address",
  ]
  /// 가게 값을 끊는 다른 항목 머리말(낱말 같음, 또는 바로 뒤가 숫자·`:`·`-`). 둘째 낱말부터 본다.
  static let storeCutWords = [
    "tel", "fax", "phone", "전화", "전화번호", "대표", "대표자", "사업자", "사업자번호", "등록번호", "주소", "승인", "승인번호", "카드", "카드번호", "일시",
  ]
  /// 머리글 낱말(줄 같음, 이어 붙인 것도 같음).
  static let headerWords: Set<String> = [
    "영수증", "신용카드매출전표", "카드매출전표", "매출전표", "카드전표", "신용카드", "체크카드", "현금영수증", "신용승인", "승인", "고객용", "가맹점용",
    "카드사용", "재발행", "거래명세서", "거래명세", "결제상세", "결제내역", "결제완료", "주문상세", "주문내역", "이용내역", "승인내역", "구매내역", "거래내역",
    "영수증보기", "상세내역", "고객님", "회원님", "안녕하세요", "어서오세요", "감사합니다", "또오세요", "receipt", "salesreceipt", "customercopy",
    "merchantcopy", "copy", "welcome", "thankyou", "thanks", "レシート", "領収書", "领收", "領収証", "お買上明細", "お買上げ明細書",
    "いらっしゃいませ", "ありがとうございました", "毎度ありがとうございます", "收据", "购物小票", "小票", "欢迎光临", "谢谢惠顾", "谢谢",
    "kassenbon", "kassenbeleg", "quittung", "rechnung", "beleg", "bon", "ticket", "ticketdecaisse", "facture", "recu",
    "reçu",
    "recibo",
    "factura", "ticketdecompra", "facturasimplificada", "scontrino", "scontrinofiscale", "ricevuta",
    "documentocommerciale",
    "danke",
    "vielendank", "merci", "gracias", "grazie", "bienvenue", "willkommen", "bienvenido", "benvenuto",
    "visa", "mastercard", "master", "amex", "americanexpress", "discover", "jcb", "unionpay", "maestro", "dinersclub",
  ]
  /// 머리글을 이어 붙일 때만 쓰는 조각 낱말. 조각 하나뿐인 줄("상세")은 머리글이 아니다.
  static let headerFragments: Set<String> = [
    "상세", "내역", "정보", "고객", "보관용", "소득공제", "지출증빙", "확인", "customer", "merchant", "sales", "transaction", "order",
    "details", "detail", "summary", "record",
  ]
  /// 문장 줄의 끝(공백 없이 끝 "!" 를 뺀 줄): "결제가 완료되었습니다", "いらっしゃいませ".
  static let sentenceEndings = [
    "니다", "니다.", "세요", "세요.", "십시오", "십시오.", "요.", "ます", "ました", "ませ", "ません", "ください", "下さい", "です",
  ]
  /// 화면 버튼·탐색 낱말(줄 같음).
  static let buttonWords: Set<String> = [
    "닫기", "공유", "뒤로", "확인", "홈", "메뉴", "저장", "다운로드", "취소", "더보기", "取消", "キャンセル", "閉じる", "戻る", "共有", "保存", "关闭",
    "返回", "分享", "return", "refund", "cancel", "close", "back", "share", "save", "done", "home", "menu",
  ]
  /// 상태 막대의 통신·상태 낱말(줄 같음).
  static let statusBarWords: Set<String> = ["lte", "5g", "4g", "3g", "wifi", "sos"]
  /// 위쪽 줄 머리말(줄 머리 낱말) 중 첫 낱말이 그 말로 시작하기만 해도 머리말인 것(3자 이상 한글·한자·가나. "대표자홍길동").
  static let prefixHeadWords = [
    "대표자", "사업자", "사업자번호", "등록번호", "전화번호", "승인번호", "승인일시", "카드종류", "카드번호", "카드사", "할부개월", "일시불",
    "유효기간", "거래일시", "거래일자", "단말기", "단말기번호", "주문번호", "담당자", "판매원", "担当者", "登録番号", "收银员", "承認番号", "伝票番号",
    "会員番号", "カード会社", "取扱日",
  ]
  /// 위쪽 줄 머리말 중 첫 낱말이 같거나 바로 뒤가 숫자·`:`·`-`·`#` 일 때만 머리말인 것(2자 등. "대표떡볶이"·"카드몰"·"レジャー" 는 아니다).
  static let boundedHeadWords = [
    "대표", "전화", "승인", "카드", "할부", "담당", "직원", "캐셔", "테이블", "レジ", "電話", "担当", "电话", "地址", "收银", "单号", "台号",
  ]
  /// 영문·유럽 머리말. 첫 낱말이 같고 그 끝에 `:`·`#`·`.` 가 붙었거나 다음 낱말이 숫자·`(`·`#` 로 시작할 때만
  /// ("TEL AVIV GRILL" 은 아니다, "Kasse 3" 은 머리말).
  static let englishHeadWords = [
    "tel", "fax", "phone", "pos", "table", "order", "cashier", "server", "clerk", "telefon", "tél", "tel.", "kasse",
    "caisse",
    "cassa",
    "caja", "bediener", "operateur", "opérateur", "cajero", "cassiere", "tisch", "mesa", "tavolo", "bon", "beleg",
  ]
  /// 카드 전표 항목 머리말(라틴, 첫 낱말 같음). 줄에 `:`·`*` 나 숫자 3자 이상이 있을 때만 머리말이다
  /// ("Card Type: VISA", "Auth Code 123456", "Acct ****1234". "Cardiff Cafe"·"Type 1 Coffee" 는 아니다).
  static let cardSlipHeadWords: Set<String> = [
    "card", "cardtype", "type", "entry", "account", "acct", "auth", "approval", "appr", "aid", "tvr", "tsi", "mid",
    "tid",
    "terminal", "ref",
    "reference", "trans", "transaction", "invoice", "batch", "seq", "sequence", "merchant",
  ]
  /// 첫 낱말이 이것과 같으면(낱말 같음) 인사 줄이라 가게가 아니다("Thank you for shopping", "Merci de votre visite").
  static let greetingWords: Set<String> = [
    "thank", "thanks", "danke", "merci", "gracias", "grazie", "welcome", "willkommen", "bienvenue", "bienvenido",
    "benvenuto",
  ]
  /// 품목 머리 줄 낱말(낱말 같음 둘 이상, 또는 둘 이상 이어 붙인 줄 "品名数量金額").
  static let itemHeaderWords: Set<String> = [
    "품명", "상품명", "메뉴", "수량", "단가", "금액", "item", "qty", "price", "description", "品名", "商品名", "数量", "単価", "金額", "商品",
    "单价", "金额",
  ]
  /// 미국 주소의 거리 낱말(낱말 같음).
  static let streetWords: Set<String> = [
    "st", "street", "ave", "avenue", "rd", "road", "blvd", "dr", "drive", "way", "ln", "lane", "hwy", "pkwy", "pl",
    "ct",
    "suite",
    "ste",
  ]
  /// 유럽 주소의 거리 낱말(줄에 숫자가 있을 때). 독일어·네덜란드어는 합성어라 낱말 끝 일치("Hauptstraße"), 나머지는 낱말 같음.
  static let europeanStreetSuffixes = [
    "straße", "strasse", "str.", "weg", "platz", "allee", "gasse", "straat", "laan", "plein",
  ]
  static let europeanStreetWords: Set<String> = [
    "rue", "bd", "boulevard", "place", "allée", "chemin", "calle", "c/", "avda", "avenida", "plaza", "paseo", "via",
    "viale",
    "piazza",
    "corso",
  ]

  /// 한글·한자·가나가 든 말인지(띄어 쓰지 않는 표기라 부분 문자열로 대조하는 표에 쓴다).
  static func isCJK(_ text: some StringProtocol) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0xAC00 ... 0xD7A3).contains(scalar.value) || (0x3040 ... 0x30FF).contains(scalar.value)
        || (0x4E00 ... 0x9FFF).contains(scalar.value)
    }
  }
}
