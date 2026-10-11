import Core
import CoreGraphics
import Testing

struct RuleClassifierTests {
  @Test(
    "정보형 라벨 하나로 카테고리를 정한다",
    arguments: [
      ("coupon", ImageCategory.gifticon),
      ("gift_card", .gifticon),
      ("receipt", .receipt),
      ("shopping_cart", .shopping),
      ("map", .map),
      ("document", .document),
      ("handwriting", .document),
    ]
  )
  func classifiesInformationLabel(identifier: String, expected: ImageCategory) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [label(identifier)], textLines: [])

    #expect(categories == [expected])
  }

  @Test(
    "OCR 키워드가 기준 개수 이상이면 정보형 카테고리로 정한다",
    arguments: [
      (["스타벅스 아메리카노 T", "교환처 스타벅스", "유효기간 2026.12.31"], ImageCategory.gifticon),
      (["합계 12,000", "승인번호 12345678"], .receipt),
      (["상품 상세", "장바구니", "바로구매"], .shopping),
      (["서울역 → 강남역", "대중교통 32분", "도보 5분"], .map),
      (["홍길동", "메시지 입력"], .chat),
    ]
  )
  func classifiesKeywords(texts: [String], expected: ImageCategory) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(categories == [expected])
  }

  @Test("키워드가 기준 개수보다 적으면 정하지 않는다")
  func ignoresTooFewKeywords() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: [line("유효기간 2026.12.31"), line("합계 12,000")]
    )

    #expect(categories == [.other])
  }

  @Test("OCR 이 글자 사이를 띄워 읽어도 키워드를 찾는다")
  func matchesSpacedKeywords() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: [line("교 환 처  CU"), line("유효 기간: 2026. 12. 31")]
    )

    #expect(categories == [.gifticon])
  }

  @Test(
    "앞 단어 중간에서 시작해 공백을 넘어 걸린 키워드는 세지 않는다",
    arguments: [
      (["몇 시까지 도착해?", "나도 보고 싶어"], ImageCategory.map),
      (["검사 결과 세부 내역", "합계 3건"], .receipt),
    ]
  )
  func ignoresKeywordsAcrossWordBoundary(texts: [String], category: ImageCategory) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(!categories.contains(category))
  }

  @Test("단어 안에 붙은 키워드는 찾는다")
  func matchesKeywordInsideWord() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: [line("모바일교환권"), line("사용기한 2026.12.31")]
    )

    #expect(categories == [.gifticon])
  }

  @Test("영문 키워드는 대소문자를 가리지 않는다")
  func matchesCaseInsensitively() {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: [line("iMessage")])

    #expect(categories == [.chat])
  }

  @Test("말풍선 시각 줄이 두 개 이상이면 대화 캡처로 정한다")
  func classifiesChatTimestamps() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: [line("9:41"), line("내일 몇 시에 봐?"), line("오후 3:12"), line("7시 어때"), line("3:15 PM")]
    )

    #expect(categories == [.chat])
  }

  @Test(
    "오전·오후, AM·PM 말풍선 시각을 모두 알아본다",
    arguments: [
      ["오전 9:05", "오전 11:30"],
      ["오후 3:12", "오후 10:01"],
      ["9:05 AM", "11:30 am"],
      ["3:12 PM", "10:01 pm"],
      ["알겠어 오후 3:12", "고마워 오후 3:13"],
    ]
  )
  func recognizesChatTimestampForms(texts: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(categories == [.chat])
  }

  @Test(
    "출발·도착이 나오는 승차권·배송 조회 화면은 지도가 아니다",
    arguments: [
      ["KTX 승차권", "서울 → 부산", "출발 09:00", "도착 11:40", "경로 경부선"],
      ["배송 현황", "출발 옥천HUB", "도착 강남지점", "배송 경로"],
    ]
  )
  func ignoresDepartureArrivalText(texts: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(!categories.contains(.map))
  }

  @Test("상태 막대 시각만 있으면 대화 캡처가 아니다")
  func ignoresStatusBarTime() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: [line("9:41"), line("오후 3:12"), line("설정")]
    )

    #expect(categories == [.other])
  }

  /// 시각이 줄마다 붙는 다른 화면도 말풍선 시각 패턴에 걸린다. 정확도 측정 작업에서 규칙을 좁히면 `withKnownIssue` 를 지운다.
  @Test(
    "말풍선이 아닌 시각 줄이 여러 개인 화면은 대화 캡처가 아니다",
    arguments: [
      ["최근 통화", "엄마", "휴대전화", "오후 3:12", "김철수", "휴대전화", "오전 11:30"],
      ["알림 센터", "카카오페이", "결제가 완료되었습니다", "오후 3:12", "택배", "배송이 시작되었습니다", "오전 9:05"],
      ["10월 11일 일요일", "팀 회의", "오후 3:00 ~ 오후 4:00", "저녁 약속", "오후 7:00 ~ 오후 9:00"],
    ]
  )
  func ignoresNonChatTimestamps(texts: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    withKnownIssue("말풍선 시각 패턴이 통화 기록·알림 센터·캘린더 시각과 구분되지 않는다") {
      #expect(!categories.contains(.chat))
    }
  }

  @Test(
    "촬영 사진은 라벨로 사진형 카테고리를 정한다",
    arguments: [
      ("food", ImageCategory.food),
      ("dessert", .food),
      ("people", .people),
      ("child", .people),
      ("dog", .pet),
      ("cat", .pet),
      ("mountain", .landscape),
      ("beach", .landscape),
    ]
  )
  func classifiesPhotoLabel(identifier: String, expected: ImageCategory) {
    let categories = RuleClassifier.classify(asset: photo, labels: [label(identifier)], textLines: [])

    #expect(categories == [expected])
  }

  @Test("스크린샷에는 사진형 카테고리를 붙이지 않는다")
  func skipsPhotoCategoriesOnScreenshot() {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [label("food"), label("people")], textLines: [])

    #expect(categories == [.other])
  }

  @Test("기기 스크린샷이 아니어도 screenshot 라벨이 있으면 사진형 카테고리를 붙이지 않는다")
  func skipsPhotoCategoriesOnScreenshotLabel() {
    let categories = RuleClassifier.classify(
      asset: photo,
      labels: [label("screenshot"), label("food"), label("people")],
      textLines: []
    )

    #expect(categories == [.other])
  }

  @Test("여러 카테고리에 동시에 속할 수 있다")
  func classifiesMultipleCategories() {
    let categories = RuleClassifier.classify(
      asset: photo,
      labels: [label("receipt"), label("food"), label("people")],
      textLines: []
    )

    #expect(categories == [.receipt, .food, .people])
  }

  @Test("어떤 규칙에도 맞지 않으면 기타다")
  func classifiesOther() {
    let categories = RuleClassifier.classify(
      asset: photo,
      labels: [label("structure"), label("vehicle")],
      textLines: [line("STOP")]
    )

    #expect(categories == [.other])
  }

  @Test("여행은 규칙 분류기가 정하지 않는다")
  func neverClassifiesTravel() {
    let categories = RuleClassifier.classify(
      asset: photo,
      labels: [label("airport"), label("airplane"), label("luggage")],
      textLines: []
    )

    #expect(!categories.contains(.travel))
  }
}

private let screenshot = ImageAsset(
  id: "screenshot",
  creationDate: nil,
  coordinate: nil,
  pixelWidth: 1170,
  pixelHeight: 2532,
  isScreenshot: true
)

private let photo = ImageAsset(
  id: "photo",
  creationDate: nil,
  coordinate: Coordinate(latitude: 37.5665, longitude: 126.978),
  pixelWidth: 4032,
  pixelHeight: 3024,
  isScreenshot: false
)

private func label(_ identifier: String) -> ImageLabel {
  ImageLabel(identifier: identifier, confidence: 0.8)
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 0.9, boundingBox: .zero)
}
