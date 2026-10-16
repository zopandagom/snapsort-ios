import CoreGraphics
import Testing
@testable import Core

struct TextRecognitionPolicyTests {
  @Test("스크린샷은 라벨과 관계없이 OCR 한다")
  func recognizesScreenshot() {
    let asset = makeAsset(isScreenshot: true, coordinate: seoul)

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label("food")]))
  }

  @Test(
    "정보형·글자가 많은 라벨이 있으면 위치가 있어도 OCR 한다",
    arguments: ["document", "receipt", "coupon", "gift_card", "map", "printed_page", "screenshot", "ticket"]
  )
  func recognizesTextLabel(identifier: String) {
    let asset = makeAsset(isScreenshot: false, coordinate: seoul)

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label("outdoor"), label(identifier)]))
  }

  @Test("글자 라벨은 신뢰도 기준 이상일 때만 OCR 한다")
  func requiresTextLabelConfidence() {
    let asset = makeAsset(isScreenshot: false, coordinate: seoul)
    let minimum = ClassificationRules.textLabelMinimumConfidence

    #expect(TextRecognitionPolicy.needsTextRecognition(
      asset: asset,
      labels: [ImageLabel(identifier: "document", confidence: minimum)]
    ))
    #expect(!TextRecognitionPolicy.needsTextRecognition(
      asset: asset,
      labels: [ImageLabel(identifier: "document", confidence: minimum - 0.01)]
    ))
  }

  @Test("screenshot 라벨은 신뢰도 기준 아래여도 OCR 한다")
  func recognizesWeakScreenshotLabel() {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)
    let weakScreenshot = ImageLabel(
      identifier: "screenshot",
      confidence: ClassificationRules.textLabelMinimumConfidence - 0.1
    )

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [weakScreenshot]))
  }

  @Test("위치가 없어도 글자 라벨이 없으면 OCR 하지 않는다", arguments: [[], ["structure"], ["food"], ["people"], ["dog"]])
  func skipsImageWithoutTextLabel(identifiers: [String]) {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: identifiers.map(label)))
  }

  @Test("사진형 라벨이 함께 있어도 글자 라벨이 있으면 OCR 한다")
  func recognizesTextLabelOverPhotoLabel() {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label("people"), label("receipt")]))
  }

  @Test("위치가 있고 글자 라벨이 없는 촬영 사진은 OCR 하지 않는다")
  func skipsPhotoWithLocation() {
    let asset = makeAsset(isScreenshot: false, coordinate: seoul)

    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label("structure")]))
    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: []))
  }
}

private let seoul = Coordinate(latitude: 37.5665, longitude: 126.978)

private func makeAsset(isScreenshot: Bool, coordinate: Coordinate?) -> ImageAsset {
  ImageAsset(
    id: "asset",
    creationDate: nil,
    coordinate: coordinate,
    pixelWidth: 1170,
    pixelHeight: 2532,
    isScreenshot: isScreenshot
  )
}

private func label(_ identifier: String) -> ImageLabel {
  ImageLabel(identifier: identifier, confidence: 0.8)
}
