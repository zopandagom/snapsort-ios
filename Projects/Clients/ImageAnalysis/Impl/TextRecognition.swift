import Core
import CoreGraphics
import Vision

/// Vision OCR 설정과 결과를 다듬는 규칙.
enum TextRecognition {
  /// 읽을 언어. 앞에 둔 언어를 우선한다. 기프티콘·영수증의 한글과 브랜드·URL 의 영문을 함께 읽는다.
  static let languages = [Locale.Language(identifier: "ko-KR"), Locale.Language(identifier: "en-US")]

  /// 작은 글자(만료일·번호)까지 읽도록 정확도 우선으로 하고, 언어 모델로 철자를 보정한다.
  static func request() -> RecognizeTextRequest {
    var request = RecognizeTextRequest()
    request.recognitionLanguages = self.languages
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    return request
  }

  /// 앞뒤 공백을 빼고 빈 줄을 버린다. 위치는 이미 왼쪽 위 원점으로 바꾼 값을 받는다(`topLeftOrigin`).
  /// 줄 순서는 Vision 이 준 읽는 순서를 그대로 둔다 (여러 단 배치를 위치로 다시 정렬하면 오히려 섞인다).
  /// 신뢰도로는 거르지 않는다. 기준은 정확도 측정 작업에서 정한다.
  static func lines(_ lines: [RecognizedTextLine]) -> [RecognizedTextLine] {
    lines.compactMap { line in
      let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      return RecognizedTextLine(text: text, confidence: line.confidence, boundingBox: line.boundingBox)
    }
  }

  /// 0~1 정규화 사각형의 원점을 Vision 의 왼쪽 아래에서 `RecognizedTextLine` 이 약속한 왼쪽 위로 바꾼다.
  static func topLeftOrigin(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
  }
}
