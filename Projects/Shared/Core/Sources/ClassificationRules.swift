/// 규칙 분류기와 OCR 대상 판정이 함께 쓰는 라벨·키워드 표 (docs/ARCHITECTURE.md §4).
/// 라벨은 Vision `ClassifyImageRequest` 의 식별자다. Vision 은 상위 라벨(예: 품종 라벨과 함께 "dog")도 함께 내므로 상위 라벨 위주로 둔다.
/// 키워드는 공백 없이 소문자로 적는다. OCR 이 글자 사이를 띄워 읽어도 맞도록 대조할 때 텍스트의 공백을 무시한다.
/// 단, 공백을 넘어 걸린 키워드는 단어 시작에서 시작할 때만 인정한다(`RuleClassifier`).
/// 표의 값은 임시이며 샘플 이미지 정확도 측정 작업에서 조정한다.
/// `scripts/mask-samples.py` 가 이 파일의 `InformationRule` 마다 `keywords:` 문자열 리터럴 배열과
/// `chatTimestampPattern`·`couponNumberPattern` 정규식 리터럴을 읽어
/// 샘플을 가린다(리터럴이 아니면 실패한다).
/// 형식을 바꾸면 `make test-scripts` 로 확인한다(이 파일이 바뀌면 `/pr` 이 실행한다).
public enum ClassificationRules {
  /// 이보다 신뢰도가 낮은 이미지 분류 라벨은 규칙에 쓰지 않는다. 임시 값이며 정확도 측정 작업에서 확정한다.
  /// Vision 은 지원하는 라벨(1천 개 이상) 대부분을 신뢰도 0 에 가깝게 돌려준다.
  public static let minimumLabelConfidence: Float = 0.1

  /// 정보형 카테고리 하나의 규칙. 라벨이 `labelOnlyMinimumConfidence` 이상이거나 키워드가 기준 개수 이상 나오면 해당한다.
  /// 그 기준에 못 미치는 라벨은 키워드 하나로 센다(라벨만으로는 붙지 않고 키워드와 함께 기준 개수를 채운다).
  struct InformationRule {
    let category: ImageCategory
    let labels: Set<String>
    /// 라벨만으로 해당하는 신뢰도. nil 이면 라벨만으로는 해당하지 않는다.
    let labelOnlyMinimumConfidence: Float?
    let keywords: [String]
    let minimumKeywordMatches: Int
  }

  static let informationRules: [InformationRule] = [
    InformationRule(
      category: .gifticon,
      labels: ["coupon", "gift_card"],
      // 실기기 보관함 1,045장에 이 라벨이 붙은 이미지가 없어 근거가 없다. 빠지면 만료 알림도 빠지므로 라벨만으로 둔다.
      labelOnlyMinimumConfidence: minimumLabelConfidence,
      keywords: [
        "유효기간", "사용기한", "교환처", "교환권", "교환수량", "선물하기", "기프티콘", "기프트카드", "모바일쿠폰", "쿠폰번호",
        "쿠폰함", "코드번호", "상품권",
      ],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .receipt,
      labels: ["receipt"],
      // 책 페이지·증명서·명함·안내문·음식 사진에 영수증 키워드 없이 0.74 까지 붙는다(실기기 샘플).
      // 실제 영수증은 라벨 없이 키워드로 잡히는 경우가 대부분이었다(실기기 보관함 1,045장).
      labelOnlyMinimumConfidence: nil,
      // 영문 키워드는 해외 영수증용이다. "total" 은 영문 화면에 흔하고 "subtotal" 과 겹쳐 한 낱말이 둘로 세져 두지 않는다.
      // "Subtotal"·"Grand Total" 이 함께 보이는 영문 쇼핑몰 주문 요약 화면은 영수증이 된다(한계).
      keywords: [
        "영수증", "합계", "총액", "결제금액", "받을금액", "승인번호", "승인일시", "부가세", "과세", "면세",
        "카드번호", "가맹점", "사업자번호", "사업자등록번호", "거래일시", "receipt", "subtotal", "grandtotal", "amountdue",
        "changedue",
      ],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .chat,
      labels: [],
      labelOnlyMinimumConfidence: nil,
      keywords: ["메시지입력", "문자메시지"],
      minimumKeywordMatches: 1
    ),
    InformationRule(
      category: .shopping,
      labels: ["shopping_cart"],
      // 기프티콘과 같이 실기기 보관함에 이 라벨이 붙은 이미지가 없어 라벨만으로 둔다.
      labelOnlyMinimumConfidence: minimumLabelConfidence,
      keywords: ["장바구니", "구매하기", "바로구매", "주문하기", "결제하기", "무료배송", "배송비", "배송조회", "옵션선택", "할인가", "쿠폰받기"],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .map,
      labels: ["map"],
      // 지도 화면 캡처는 키워드 없이 강하게(0.88) 붙는 경우가 있다(실기기 보관함). 약한 라벨만 키워드를 함께 본다. 임시 값.
      labelOnlyMinimumConfidence: 0.5,
      keywords: ["길찾기", "대중교통", "도보", "지도"],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .document,
      labels: [
        "document", "printed_page", "handwriting", "newspaper", "magazine", "sticky_note", "whiteboard", "chalkboard",
        "chart", "diagram", "calendar",
      ],
      // 문서는 라벨에 더해 OCR 글자 수를 본다(`minimumDocumentTextLength`).
      labelOnlyMinimumConfidence: minimumLabelConfidence,
      keywords: [],
      minimumKeywordMatches: 1
    ),
  ]

  /// 대화 캡처에서 말풍선 옆에 따로 한 줄로 읽히는 시각(예: "오후 3:12"). 정규화한 줄 전체에 대조한다.
  /// 앞뒤의 숫자 1~2자리는 OCR 이 시각과 붙여 읽은 안 읽은 수("1오후 3:12", "오전 11:182")다.
  /// 상태 막대 시각("9:41")은 오전·오후 표시가 없고, 문장 속 시각("미사 오전 11:30")은 줄 전체가 아니어서 걸리지 않는다.
  /// 영문 AM·PM 은 탑승권·예약 확인 화면의 시각과 구분되지 않아(실기기 보관함 샘플) 세지 않는다.
  /// `Regex` 가 `Sendable` 이 아니어서 정적 저장 프로퍼티 대신 계산 프로퍼티로 둔다. 쓰는 쪽은 한 번 만들어 재사용한다.
  static var chatTimestampPattern: Regex<Substring> { #/\d{0,2}오[전후]\d{1,2}:\d{2}\d{0,2}/# }

  /// 기프티콘 쿠폰 번호만 있는 줄(예: "1234 - 5678 - 9012", "123456789012"). 정규화한 줄 전체에 대조하고, 있으면 기프티콘 키워드 하나로 센다.
  /// 저장한 기프티콘 이미지는 상품 사진·브랜드·유효기간·번호뿐이라 키워드가 "유효기간" 하나인 경우가 있다(실기기 보관함).
  /// 4자리씩 12·16자리이고 묶음 사이는 줄표만 허용한다(공백은 정규화로 지워진다). 전화·사업자·계좌 번호는 묶음 자리가 달라 걸리지 않고,
  /// 가린 카드 번호("1234-****-…")도 걸리지 않는다. 번호 옆 복사 아이콘을 OCR 이 글자 하나로 붙여 읽어(사용자 기기) 끝의 숫자 아닌 글자 하나는 허용한다.
  /// 멤버십 카드 번호와 "유효기간"이 함께 있는 화면은 기프티콘이 된다(한계).
  /// `scripts/mask-samples.py` 가 이 정규식 리터럴을 읽어, 이 줄은 숫자를 0 으로 바꾸고 줄표·공백을 남긴다.
  static var couponNumberPattern: Regex<Substring> { #/\d{4}(?:[-–]?\d{4}){2,3}\D?/# }

  /// 대화 캡처로 보는 말풍선 시각 줄 수. 시각은 대체로 오름차순이어야 한다(`RuleClassifier`).
  /// 최신순으로 쌓이는 통화 기록·알림 센터와 시각이 뒤섞인 항공권을 거른다.
  static let minimumChatTimestampLines = 2

  /// 정보형 라벨로 문서를 정할 때 필요한 OCR 글자 수(공백 제외). 사람·물건 사진에 약하게 붙는 `document` 라벨을 거른다.
  static let minimumDocumentTextLength = 30

  /// 사진형 카테고리별 라벨 신뢰도 기준. 없으면 `minimumLabelConfidence` 를 쓴다.
  /// 인물·풍경 라벨은 신뢰도가 낮을 때 그림·음식·동물 사진에도 붙는다(실기기 보관함 샘플).
  static let photoLabelMinimumConfidence: [ImageCategory: Float] = [.people: 0.3, .landscape: 0.4]

  /// 그림·일러스트에 붙는 라벨. 이 신뢰도 이상이면 그린 인물·동물을 사진형으로 묶지 않는다.
  static let drawingLabels: Set<String> = ["illustrations", "painting"]
  static let drawingMinimumConfidence: Float = 0.5

  /// OCR 대상 판정에서 `screenshot` 밖의 글자 라벨이 넘어야 하는 신뢰도.
  /// 식탁 위 메뉴판·만화·그림·물건 사진에 약하게 붙는 `document`·`printed_page` 라벨로 OCR 하지 않는다
  /// (실기기 보관함: 이 기준 미만 라벨로만 OCR 해 문서가 된 이미지는 대부분 이런 사진이었다).
  /// `screenshot` 라벨은 저장한 기프티콘 캡처에 0.2 안팎으로 붙어 기준을 두지 않는다.
  static let textLabelMinimumConfidence: Float = 0.3

  /// 사진형 카테고리를 정하는 라벨. 여행은 위치·날짜로 판정하므로 여기 없다.
  static let photoLabels: [ImageCategory: Set<String>] = [
    .food: ["food", "dessert", "drink", "baked_goods"],
    .people: ["people", "adult", "child", "baby", "teen"],
    .pet: ["dog", "cat", "hamster", "rabbit"],
    .landscape: [
      "sky", "blue_sky", "sunset_sunrise", "night_sky", "aurora", "mountain", "hill", "cliff", "canyon", "desert",
      "glacier", "beach", "shore", "ocean", "lake", "river", "waterfall", "island", "forest", "rice_field", "cityscape",
    ],
  ]

  /// 화면을 캡처한 이미지에 붙는 라벨. 기기 스크린샷이 아니어도 사진형 카테고리를 막는 데 쓴다.
  static let screenshotLabel = "screenshot"

  /// 카테고리는 아니지만 글자가 많아 OCR 할 만한 라벨.
  static let textHeavyLabels: Set<String> = [screenshotLabel, "ticket", "credit_card", "passport", "envelope"]

  /// OCR 대상으로 보는 라벨: 정보형 카테고리 라벨 + 글자가 많은 라벨.
  /// `screenshot` 밖의 라벨은 `textLabelMinimumConfidence` 이상이어야 한다(`TextRecognitionPolicy`).
  static let textLabels: Set<String> = informationRules.reduce(into: textHeavyLabels) { $0.formUnion($1.labels) }

  /// 공백을 지우고 소문자로 바꾼다. 말풍선 시각·쿠폰 번호 패턴 대조와 키워드 표 형식 검사에 쓴다.
  static func normalize(_ text: String) -> String {
    String(text.lowercased().filter { !$0.isWhitespace })
  }
}
