/// 규칙 분류기와 OCR 대상 판정이 함께 쓰는 라벨·키워드 표 (docs/ARCHITECTURE.md §4).
/// 라벨은 Vision `ClassifyImageRequest` 의 식별자다. Vision 은 상위 라벨(예: 품종 라벨과 함께 "dog")도 함께 내므로 상위 라벨 위주로 둔다.
/// 키워드는 공백 없이 소문자로 적는다. OCR 이 글자 사이를 띄워 읽어도 맞도록 대조할 때 텍스트의 공백을 무시한다.
/// 단, 공백을 넘어 걸린 키워드는 단어 시작에서 시작할 때만 인정한다(`RuleClassifier`).
/// 표의 값은 임시이며 샘플 이미지 정확도 측정 작업에서 조정한다.
enum ClassificationRules {
  /// 정보형 카테고리 하나의 규칙. 라벨이 하나라도 있거나 키워드가 기준 개수 이상 나오면 해당한다.
  struct InformationRule {
    let category: ImageCategory
    let labels: Set<String>
    let keywords: [String]
    let minimumKeywordMatches: Int
  }

  static let informationRules: [InformationRule] = [
    InformationRule(
      category: .gifticon,
      labels: ["coupon", "gift_card"],
      keywords: ["유효기간", "사용기한", "교환처", "교환권", "선물하기", "기프티콘", "기프트카드", "모바일쿠폰", "쿠폰번호", "상품권"],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .receipt,
      labels: ["receipt"],
      keywords: [
        "영수증", "합계", "총액", "결제금액", "받을금액", "승인번호", "승인일시", "부가세", "과세", "면세",
        "카드번호", "가맹점", "사업자번호", "사업자등록번호", "거래일시",
      ],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .chat,
      labels: [],
      keywords: ["메시지입력", "imessage", "문자메시지"],
      minimumKeywordMatches: 1
    ),
    InformationRule(
      category: .shopping,
      labels: ["shopping_cart"],
      keywords: ["장바구니", "구매하기", "바로구매", "주문하기", "결제하기", "무료배송", "배송비", "배송조회", "옵션선택", "할인가", "쿠폰받기"],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .map,
      labels: ["map"],
      keywords: ["길찾기", "대중교통", "도보", "지도"],
      minimumKeywordMatches: 2
    ),
    InformationRule(
      category: .document,
      labels: [
        "document", "printed_page", "handwriting", "newspaper", "magazine", "sticky_note", "whiteboard", "chalkboard",
        "chart", "diagram", "calendar",
      ],
      keywords: [],
      minimumKeywordMatches: 1
    ),
  ]

  /// 대화 캡처에서 말풍선마다 붙는 시각(예: "오후 3:12", "3:12 PM"). 정규화한 줄 텍스트에 대조한다.
  /// 상태 막대 시각("9:41")은 오전·오후 표시가 없어 걸리지 않는다.
  /// `Regex` 가 `Sendable` 이 아니어서 정적 저장 프로퍼티 대신 계산 프로퍼티로 둔다. 쓰는 쪽은 한 번 만들어 재사용한다.
  static var chatTimestampPattern: Regex<Substring> { #/오[전후]\d{1,2}:\d{2}|\d{1,2}:\d{2}[ap]m/# }
  /// 대화 캡처로 보는 말풍선 시각 줄 수.
  static let minimumChatTimestampLines = 2

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
  static let textLabels: Set<String> = informationRules.reduce(into: textHeavyLabels) { $0.formUnion($1.labels) }

  /// 사진형 카테고리 라벨 전체. 위치 없는 이미지가 촬영 사진인지 가르는 데 쓴다.
  static let allPhotoLabels: Set<String> = photoLabels.values.reduce(into: []) { $0.formUnion($1) }

  /// 공백을 지우고 소문자로 바꾼다. 말풍선 시각 패턴 대조와 키워드 표 형식 검사에 쓴다.
  static func normalize(_ text: String) -> String {
    String(text.lowercased().filter { !$0.isWhitespace })
  }
}
