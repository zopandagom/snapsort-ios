import Core
import CoreGraphics
import Testing

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

  @Test("위치도 사진형 라벨도 없는 저장 이미지는 OCR 한다")
  func recognizesSavedImageWithoutLocation() {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label("structure")]))
    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: []))
  }

  @Test("위치가 없어도 인물·반려동물·풍경 라벨이 있으면 OCR 하지 않는다", arguments: ["people", "dog", "mountain"])
  func skipsPhotoWithoutLocation(identifier: String) {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label(identifier)]))
  }

  @Test("위치가 없고 사진형 라벨과 글자 라벨이 함께 있으면 OCR 한다")
  func recognizesTextLabelOverPhotoLabel() {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label("food"), label("receipt")]))
  }

  @Test("위치 없는 이미지의 사진형 판단은 규칙 분류기와 같은 기준이다: 약한 인물 라벨·그림은 촬영 사진으로 보지 않는다")
  func usesClassifierPhotoCriteria() {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)
    let weakPeople = ImageLabel(identifier: "people", confidence: 0.2)
    let drawing = [ImageLabel(identifier: "illustrations", confidence: 0.7), label("dog")]

    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [weakPeople]))
    #expect(TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: drawing))
  }

  /// 한계: 상품 사진이 든 저장 기프티콘에 음식 라벨만 붙으면 촬영 사진과 구분하지 못해 OCR 하지 않는다
  /// (OCR 대상을 늘리는 비용과 함께 OCR 대상 조정 작업에서 정한다. TextRecognitionPolicy 문서 주석, 정확도 샘플의 knownIssue).
  @Test("위치가 없어도 음식 라벨만 있으면 촬영 사진으로 보고 OCR 하지 않는다", arguments: ["food", "drink", "dessert"])
  func skipsImageWithOnlyFoodLabel(identifier: String) {
    let asset = makeAsset(isScreenshot: false, coordinate: nil)

    #expect(!TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: [label(identifier)]))
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
