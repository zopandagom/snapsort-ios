import CoreGraphics
import Testing
@testable import Core

struct RuleClassifierTests {
  @Test(
    "정보형 라벨 하나로 카테고리를 정한다",
    arguments: [
      ("coupon", ImageCategory.gifticon),
      ("gift_card", .gifticon),
      ("shopping_cart", .shopping),
      ("map", .map),
    ]
  )
  func classifiesInformationLabel(identifier: String, expected: ImageCategory) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [label(identifier)], textLines: [])

    #expect(categories == [expected])
  }

  @Test("문서 라벨은 OCR 글자가 기준 이상일 때만 문서로 정한다", arguments: ["document", "handwriting"])
  func classifiesDocumentLabelWithEnoughText(identifier: String) {
    let text = String(repeating: "가", count: ClassificationRules.minimumDocumentTextLength)
    let enough = RuleClassifier.classify(asset: photo, labels: [label(identifier)], textLines: [line(text)])
    let tooShort = RuleClassifier.classify(
      asset: photo,
      labels: [label(identifier)],
      textLines: [line(String(text.dropFirst()))]
    )

    #expect(enough == [.document])
    #expect(tooShort == [.other])
  }

  @Test(
    "OCR 키워드가 기준 개수 이상이면 정보형 카테고리로 정한다",
    arguments: [
      (["스타벅스 아메리카노 T", "교환처 스타벅스", "유효기간 2026.12.31"], ImageCategory.gifticon),
      (["합계 12,000", "승인번호 12345678"], .receipt),
      (["상품 상세", "장바구니", "바로구매"], .shopping),
      (["서울역 → 강남역", "대중교통 32분", "도보 5분"], .map),
      (["홍길동", "메시지 입력"], .chat),
      (["내 쿠폰함", "000000000000 코드번호 복사", "스타벅스"], .gifticon),
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

  @Test("말풍선 시각 줄이 두 개 이상이면 대화 캡처로 정한다")
  func classifiesChatTimestamps() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: [line("9:41"), line("내일 몇 시에 봐?"), line("오후 3:12"), line("7시 어때"), line("오후 3:15")]
    )

    #expect(categories == [.chat])
  }

  @Test(
    "오전·오후 말풍선 시각을 안 읽은 수가 붙어도 알아본다",
    arguments: [
      ["오전 9:05", "오전 11:30"],
      ["오후 3:12", "오후 10:01"],
      ["오전 11:59", "오후 12:01"],
      ["1오후 3:12", "오후 3:13 2"],
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

  /// 통화 기록·알림 센터는 최신순이라 시각이 줄고, 항공권은 시각이 뒤섞이며, 캘린더·안내문은 시각이 문장 속에 있다.
  /// 탑승권은 영문 AM·PM 이라 세지 않는다.
  @Test(
    "말풍선이 아닌 시각 줄이 여러 개인 화면은 대화 캡처가 아니다",
    arguments: [
      ["최근 통화", "엄마", "휴대전화", "오후 3:12", "김철수", "휴대전화", "오전 11:30"],
      ["알림 센터", "카카오페이", "결제가 완료되었습니다", "오후 3:12", "택배", "배송이 시작되었습니다", "오전 9:05"],
      ["10월 11일 일요일", "팀 회의", "오후 3:00 ~ 오후 4:00", "저녁 약속", "오후 7:00 ~ 오후 9:00"],
      ["출발", "오후 5:20", "오전 1:40", "가는 편", "오후 8:10", "오전 7:35"],
      ["Boarding Pass", "Boarding", "8:20 am", "Departs", "9:05 am"],
      ["평일 운영 - 오전 10:30", "주말 운영 - 오전 11:00"],
    ]
  )
  func ignoresNonChatTimestamps(texts: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(!categories.contains(.chat))
  }

  @Test("자정을 넘긴 대화도 시각이 늘어난 것으로 본다")
  func classifiesChatAcrossMidnight() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: ["오후 11:58", "자?", "오전 12:03"].map(line)
    )

    #expect(categories == [.chat])
  }

  @Test("OCR 이 좌우 말풍선 순서를 조금 섞어도 시각이 대체로 늘면 대화 캡처다")
  func classifiesMostlyRisingTimestamps() {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: [],
      textLines: ["오후 7:21", "잘 들어갔어?", "오후 7:19", "응 고마워", "오후 7:21", "오후 7:22"].map(line)
    )

    #expect(categories == [.chat])
  }

  @Test("여러 카테고리에 동시에 속할 수 있다")
  func classifiesMultipleCategories() {
    let categories = RuleClassifier.classify(
      asset: photo,
      labels: [label("map"), label("food"), label("people")],
      textLines: []
    )

    #expect(categories == [.map, .food, .people])
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

  @Test(
    "라벨이 같으면 OCR 전 결과에 줄을 더해도 기타 밖의 카테고리가 빠지지 않는다",
    arguments: [
      (screenshot, ["receipt"]),
      (screenshot, ["map"]),
      (screenshot, ["screenshot"]),
      (photo, ["food"]),
      (photo, ["document", "dog"]),
    ]
  )
  func addingLinesOnlyAddsCategories(asset: ImageAsset, identifiers: [String]) {
    let labels = identifiers.map(label)
    let withoutText = RuleClassifier.classify(asset: asset, labels: labels, textLines: [])
    let withText = RuleClassifier.classify(
      asset: asset,
      labels: labels,
      textLines: ["교환처 GS25", "유효기간 2026.12.31", "오후 3:12", "오후 3:13", "합계 9,000", "영수증"].map(line)
    )

    #expect(withoutText.subtracting([.other]).isSubset(of: withText))
  }
}

/// 사진형 카테고리(라벨·신뢰도 기준·그림·스크린샷) 규칙.
struct RuleClassifierPhotoTests {
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

  @Test(
    "인물·풍경 라벨은 카테고리별 신뢰도 기준 이상일 때만 쓴다",
    arguments: [("people", ImageCategory.people), ("sky", .landscape)]
  )
  func usesPhotoLabelMinimumConfidence(identifier: String, category: ImageCategory) throws {
    let minimum = try #require(ClassificationRules.photoLabelMinimumConfidence[category])
    let atMinimum = RuleClassifier.classify(
      asset: photo,
      labels: [ImageLabel(identifier: identifier, confidence: minimum)],
      textLines: []
    )
    let below = RuleClassifier.classify(
      asset: photo,
      labels: [ImageLabel(identifier: identifier, confidence: minimum - 0.01)],
      textLines: []
    )

    #expect(atMinimum == [category])
    #expect(below == [.other])
  }

  @Test("인물이 있으면 하늘·바다가 보여도 풍경을 붙이지 않는다")
  func skipsLandscapeWithPeople() {
    let categories = RuleClassifier.classify(asset: photo, labels: [label("people"), label("sky")], textLines: [])

    #expect(categories == [.people])
  }

  @Test("그림·일러스트에는 사진형 카테고리를 붙이지 않는다", arguments: ["illustrations", "painting"])
  func skipsPhotoCategoriesOnDrawing(identifier: String) {
    let drawing = RuleClassifier.classify(
      asset: photo,
      labels: [
        ImageLabel(identifier: identifier, confidence: ClassificationRules.drawingMinimumConfidence),
        label("dog"),
      ],
      textLines: []
    )
    let faintDrawing = RuleClassifier.classify(
      asset: photo,
      labels: [
        ImageLabel(identifier: identifier, confidence: ClassificationRules.drawingMinimumConfidence - 0.01),
        label("dog"),
      ],
      textLines: []
    )

    #expect(drawing == [.other])
    #expect(faintDrawing == [.pet])
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
