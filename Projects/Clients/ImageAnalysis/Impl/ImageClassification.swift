import Core

/// Vision 이미지 분류 결과를 다듬는 규칙.
enum ImageClassification {
  /// 이보다 신뢰도가 낮은 라벨은 뺀다. 임시 값이고, 정확도 측정 작업에서 확정한다.
  /// Vision 은 지원하는 라벨(1천 개 이상) 대부분을 신뢰도 0 에 가깝게 돌려준다.
  static let minimumConfidence: Float = 0.1

  /// 기준 미만을 빼고 신뢰도 높은 순으로 정렬한다. 신뢰도가 같으면 식별자 순으로 두어 결과가 항상 같게 한다.
  static func labels(_ labels: [ImageLabel]) -> [ImageLabel] {
    labels
      .filter { $0.confidence >= self.minimumConfidence }
      .sorted { lhs, rhs in
        lhs.confidence != rhs.confidence ? lhs.confidence > rhs.confidence : lhs.identifier < rhs.identifier
      }
  }
}
