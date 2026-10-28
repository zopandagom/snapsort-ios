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

  // MARK: - 바코드 확인

  @Test("위치가 없고 라벨로 OCR 대상이 아니면 바코드를 확인한다", arguments: [[], ["structure"], ["food"], ["people"]])
  func checksBarcodeWithoutLocation(identifiers: [String]) {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(TextRecognitionPolicy.needsBarcodeCheck(asset: asset, labels: identifiers.map(label)))
  }

  @Test("위치가 있으면 바코드를 확인하지 않는다")
  func skipsBarcodeCheckWithLocation() {
    let asset = makeAsset(isScreenshot: false, coordinate: seoul)

    #expect(!TextRecognitionPolicy.needsBarcodeCheck(asset: asset, labels: [label("food")]))
    #expect(!TextRecognitionPolicy.needsBarcodeCheck(asset: asset, labels: []))
  }

  @Test("이미 OCR 대상이면 바코드를 확인하지 않는다")
  func skipsBarcodeCheckForTextImage() {
    let photo = makeAsset(isScreenshot: false, coordinate: nil)
    let screenshot = makeAsset(isScreenshot: true, coordinate: nil)

    #expect(!TextRecognitionPolicy.needsBarcodeCheck(asset: screenshot, labels: [label("food")]))
    #expect(!TextRecognitionPolicy.needsBarcodeCheck(asset: photo, labels: [label("screenshot")]))
    #expect(!TextRecognitionPolicy.needsBarcodeCheck(asset: photo, labels: [label("food"), label("document")]))
  }

  @Test("글자 라벨이 기준 아래인 위치 없는 이미지는 바코드를 확인한다")
  func checksBarcodeForWeakTextLabel() {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)
    // 저장한 기프티콘처럼 음식 라벨이 강하고 문서 라벨이 약하다.
    let labels = [
      label("food"),
      ImageLabel(identifier: "document", confidence: 0.109),
    ]

    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: labels))
    #expect(TextRecognitionPolicy.needsBarcodeCheck(asset: asset, labels: labels))
  }

  @Test("바코드를 찾으면 확인 대상만 OCR 한다")
  func recognizesWithBarcode() {
    let unlocated = makeAsset(isScreenshot: false, coordinate: nil)
    let located = makeAsset(isScreenshot: false, coordinate: seoul)

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: unlocated, labels: [label("food")], hasBarcode: true))
    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: located, labels: [label("food")], hasBarcode: true))
  }

  @Test("바코드가 없으면 라벨·메타데이터 판정과 같다")
  func matchesLabelPolicyWithoutBarcode() {
    let cases: [(ImageAsset, [ImageLabel])] = [
      (makeAsset(isScreenshot: true, coordinate: nil), [label("food")]),
      (makeAsset(isScreenshot: false, coordinate: nil), [label("document")]),
      (makeAsset(isScreenshot: false, coordinate: nil), [label("food")]),
      (makeAsset(isScreenshot: false, coordinate: seoul), [label("food")]),
    ]

    for (asset, labels) in cases {
      #expect(
        TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: labels, hasBarcode: false)
          == TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: labels)
      )
    }
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
