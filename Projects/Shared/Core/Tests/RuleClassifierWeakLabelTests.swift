import CoreGraphics
import Testing
@testable import Core

struct RuleClassifierWeakLabelTests {
  /// 책 페이지·증명서·명함 같은 문서와 음식 사진에 영수증 키워드 없이 `receipt` 라벨이 0.74 까지 붙었다(실기기 샘플).
  @Test("영수증 라벨만으로는 영수증이 아니고, 키워드 하나와 함께면 영수증이다", arguments: [Float(0.12), 0.74, 0.99])
  func receiptLabelCountsAsOneKeyword(confidence: Float) {
    let labels = [ImageLabel(identifier: "receipt", confidence: confidence)]
    let labelOnly = RuleClassifier.classify(asset: screenshot, labels: labels, textLines: [line("제1장 ○○○○")])
    let withKeyword = RuleClassifier.classify(asset: screenshot, labels: labels, textLines: [line("합계 12,000")])

    #expect(labelOnly == [.other])
    #expect(withKeyword == [.receipt])
  }

  @Test("영수증 키워드 하나만으로는 영수증이 아니다")
  func singleReceiptKeywordWithoutLabelIsNotReceipt() {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: [line("합계 3건")])

    #expect(categories == [.other])
  }

  @Test(
    "영문 영수증 키워드로 영수증을 정한다",
    arguments: [
      (["RECEIPT", "SUBTOTAL 12.00"], [String]()),
      (["Grand Total 15.40", "Change Due 4.60"], []),
      (["Amount Due 9.50"], ["receipt"]),
    ]
  )
  func classifiesEnglishReceipt(text: [String], identifiers: [String]) {
    let categories = RuleClassifier.classify(
      asset: screenshot,
      labels: identifiers.map(label),
      textLines: text.map(line)
    )

    #expect(categories == [.receipt])
  }

  @Test(
    "영문 영수증 키워드 하나나 영문 화면의 \"total\" 만으로는 영수증이 아니다",
    arguments: [
      ["Subtotal 12.00", "Proceed to checkout"],
      ["Total 3 items", "Order summary"],
      ["Your receipts", "Settings"],
    ]
  )
  func singleEnglishKeywordIsNotReceipt(text: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: text.map(line))

    #expect(categories == [.other])
  }

  /// 기프티콘·쇼핑 라벨은 실기기 보관함에 붙은 이미지가 없어 근거 없이 기준을 올리지 않는다. 기프티콘이 빠지면 만료 알림도 빠진다.
  @Test(
    "기프티콘·쇼핑 라벨은 분류 신뢰도 기준만 넘으면 라벨만으로 정한다",
    arguments: [("coupon", ImageCategory.gifticon), ("gift_card", .gifticon), ("shopping_cart", .shopping)]
  )
  func weakGifticonAndShoppingLabelsClassifyAlone(identifier: String, expected: ImageCategory) {
    let labels = [ImageLabel(identifier: identifier, confidence: ClassificationRules.minimumLabelConfidence)]

    #expect(RuleClassifier.classify(asset: screenshot, labels: labels, textLines: []) == [expected])
  }

  @Test("지도 라벨은 기준 이상이면 라벨만으로, 미만이면 키워드 하나와 함께일 때 지도다")
  func weakMapLabelNeedsKeyword() throws {
    let minimum = try #require(ClassificationRules.informationRules.first { $0.category == .map }?
      .labelOnlyMinimumConfidence)
    let strong = [ImageLabel(identifier: "map", confidence: minimum)]
    let weak = [ImageLabel(identifier: "map", confidence: minimum - 0.01)]

    #expect(RuleClassifier.classify(asset: screenshot, labels: strong, textLines: []) == [.map])
    #expect(RuleClassifier.classify(asset: screenshot, labels: weak, textLines: []) == [.other])
    #expect(RuleClassifier.classify(asset: screenshot, labels: weak, textLines: [line("도보 12분")]) == [.map])
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

private func label(_ identifier: String) -> ImageLabel {
  ImageLabel(identifier: identifier, confidence: 0.8)
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 0.9, boundingBox: .zero)
}
