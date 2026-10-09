import Core
import CoreGraphics
import ImageAnalysisInterface
import Testing
import UIKit
import Vision
@testable import ImageAnalysisImpl

struct TextRecognitionTests {
  @Test("한국어를 영어보다 우선해 읽고, 정확도 우선으로 철자를 보정한다")
  func configuresRequest() {
    let request = TextRecognition.request()

    #expect(request.recognitionLanguages.map(\.maximalIdentifier) == ["ko-Kore-KR", "en-Latn-US"])
    #expect(request.recognitionLevel == .accurate)
    #expect(request.usesLanguageCorrection)
  }

  @Test("앞뒤 공백을 빼고 빈 줄을 버리며, 줄 순서와 위치는 그대로 둔다")
  func trimsAndDropsEmptyLines() {
    let box = CGRect(x: 0, y: 0, width: 1, height: 0.1)
    let lines = TextRecognition.lines([
      RecognizedTextLine(text: "  유효기간 2026.12.31 ", confidence: 0.9, boundingBox: box),
      RecognizedTextLine(text: " \n", confidence: 0.5, boundingBox: box),
      RecognizedTextLine(text: "", confidence: 0.5, boundingBox: box),
      RecognizedTextLine(text: "SnapSort", confidence: 0.01, boundingBox: box),
    ])

    #expect(lines.map(\.text) == ["유효기간 2026.12.31", "SnapSort"])
    #expect(lines.map(\.confidence) == [0.9, 0.01])
    #expect(lines.map(\.boundingBox) == [box, box])
  }

  @Test("위치의 원점을 왼쪽 아래에서 왼쪽 위로 바꾼다")
  func convertsToTopLeftOrigin() {
    let rect = TextRecognition.topLeftOrigin(CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.2))

    #expect(abs(rect.minX - 0.1) < 1e-9)
    #expect(abs(rect.minY - 0.1) < 1e-9)
    #expect(abs(rect.width - 0.5) < 1e-9)
    #expect(abs(rect.height - 0.2) < 1e-9)
  }

  @Test("취소된 Task 에서는 읽지 않고 취소로 끝난다")
  func skipsRecognitionWhenCancelled() async {
    let task = Task { () async -> Result<[RecognizedTextLine], ImageAnalysisError> in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        let lines = try await ImageAnalysisClientImpl().recognizeText(.stub())
        return .success(lines)
      } catch {
        return .failure(error)
      }
    }

    #expect(await task.value == .failure(.cancelled))
  }

  @Test("그린 한국어·영어 텍스트를 읽고 위쪽 줄의 위치를 왼쪽 위 원점으로 준다")
  func recognizesRenderedText() async throws {
    // 언어 보정이 철자를 바꾸지 않도록 사전에 있는 단어를 쓰고, 대소문자는 무시하고 비교한다.
    let image = Self.render(lines: ["Coffee 2026", "유효기간"])

    let lines = try await ImageAnalysisClientImpl().recognizeText(image)

    let first = try #require(lines.first { $0.text.localizedCaseInsensitiveContains("coffee") })
    #expect(first.boundingBox.minY < 0.5)
    #expect(lines.contains { $0.text.contains("유효기간") })
  }

  /// 흰 바탕에 검은 글자를 위에서부터 한 줄씩 그린다.
  private static func render(lines: [String]) -> AnalysisImage {
    let size = CGSize(width: 800, height: 400)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      for (index, line) in lines.enumerated() {
        (line as NSString).draw(
          at: CGPoint(x: 40, y: 40 + CGFloat(index) * 160),
          withAttributes: [.font: UIFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: UIColor.black]
        )
      }
    }
    // 그린 이미지는 항상 CGImage 를 갖는다. 없으면 테스트 설정이 잘못된 것이다.
    guard let cgImage = image.cgImage else { preconditionFailure("텍스트 이미지를 만들 수 없음") }
    return AnalysisImage(cgImage: cgImage, orientation: .up)
  }
}
