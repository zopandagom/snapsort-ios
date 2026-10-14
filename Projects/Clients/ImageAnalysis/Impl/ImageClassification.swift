import Core

/// Vision 이미지 분류 결과를 다듬는 규칙.
enum ImageClassification {
  /// `minimumConfidence` 미만을 빼고 신뢰도 높은 순으로 정렬한다. 신뢰도가 같으면 식별자 순으로 두어 결과가 항상 같게 한다.
  /// 분류에 쓰는 기준은 Core `ClassificationRules.minimumLabelConfidence` 다.
  static func labels(_ labels: [ImageLabel], minimumConfidence: Float) -> [ImageLabel] {
    labels
      .filter { $0.confidence >= minimumConfidence }
      .sorted { lhs, rhs in
        lhs.confidence != rhs.confidence ? lhs.confidence > rhs.confidence : lhs.identifier < rhs.identifier
      }
  }
}
