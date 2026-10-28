import CoreGraphics
import Testing
@testable import Core

/// 쿠폰 번호 줄과 저장한 기프티콘 이미지 규칙.
struct RuleClassifierCouponTests {
  @Test(
    "쿠폰 번호만 있는 줄은 기프티콘 키워드 하나로 센다",
    arguments: [
      ["메가MGC커피", "(ICE)아메리카노", "유효기간 : 2026.10.04 ~ 2027.01.05", "0000 - 0000 - 0000"],
      ["[아이넘버&페이즈] 유효기간 만료 안내", "0000-0000-0000"],
      ["유효기간 2026.12.31", "000000000000"],
      ["유효기간 2026.12.31", "0000 0000 0000 0000"],
      ["유효기간 2026.12.31", "0000–0000–0000"],
      ["[아이넘버&페이즈] 유효기간 만료 안내", "0000-0000-0000 ○"],
    ]
  )
  func countsCouponNumberLine(texts: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(categories == [.gifticon])
  }

  @Test(
    "쿠폰 번호 모양이 아니거나 줄 전체가 아니면 세지 않는다",
    arguments: [
      ["0000-0000-0000"],
      ["유효기간 2026.12.31", "000000000000 번호 복사 안내"],
      ["유효기간 2026.12.31", "010-0000-0000"],
      ["유효기간 2026.12.31", "0000-****-****-0000"],
      ["유효기간 2026.12.31", "00000000000"],
      ["유효기간 2026.12.31", "0000000000000"],
      ["유효기간 2026.12.31", "000-000-000000"],
      ["유효기간 2026.12.31", "0000-0000-0000 ○○"],
    ]
  )
  func ignoresNonCouponNumberLine(texts: [String]) {
    let categories = RuleClassifier.classify(asset: screenshot, labels: [], textLines: texts.map(line))

    #expect(categories == [.other])
  }

  @Test("저장한 기프티콘 이미지에는 음식과 기프티콘이 함께 붙는다")
  func classifiesSavedGifticonWithFood() {
    let saved = ImageAsset(
      id: "saved",
      creationDate: nil,
      coordinate: nil,
      pixelWidth: 1334,
      pixelHeight: 2000,
      isScreenshot: false
    )
    let categories = RuleClassifier.classify(
      asset: saved,
      labels: [label("drink")],
      textLines: [line("유효기간 : 2026.10.04 ~ 2027.01.05"), line("0000 - 0000 - 0000")]
    )

    #expect(categories == [.gifticon, .food])
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
