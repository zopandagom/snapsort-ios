/// Vision 이미지 분류 라벨 하나 (docs/ARCHITECTURE.md §4). 규칙 분류기가 카테고리를 고르는 입력이다.
public struct ImageLabel: Sendable, Hashable, Codable {
  /// Vision 분류 식별자 (예: "food", "document").
  public let identifier: String
  /// 0~1 사이 신뢰도.
  public let confidence: Float

  public init(identifier: String, confidence: Float) {
    self.identifier = identifier
    self.confidence = confidence
  }
}
