import CoreGraphics

/// OCR 로 읽은 텍스트 한 줄 (docs/ARCHITECTURE.md §4). 규칙 분류기와 캡처 정보 추출(만료일·주소·번호)의 입력이다.
/// 사진에서 읽은 텍스트이므로 기기 밖으로 보내거나 로그에 남기지 않는다.
public struct RecognizedTextLine: Sendable, Hashable, Codable {
  /// 읽은 글자. 앞뒤 공백은 뺀다.
  public let text: String
  /// 0~1 사이 신뢰도.
  public let confidence: Float
  /// 이미지 안 위치. 이미지를 바르게 돌린 기준으로 0~1 정규화하고, 원점은 왼쪽 위다.
  public let boundingBox: CGRect

  public init(text: String, confidence: Float, boundingBox: CGRect) {
    self.text = text
    self.confidence = confidence
    self.boundingBox = boundingBox
  }
}
