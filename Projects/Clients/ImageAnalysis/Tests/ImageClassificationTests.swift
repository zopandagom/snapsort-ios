import Core
import ImageAnalysisInterface
import Testing
@testable import ImageAnalysisImpl

struct ImageClassificationTests {
  @Test("기준 미만 라벨을 빼고 신뢰도 높은 순으로 정렬한다")
  func filtersAndSortsLabels() {
    let labels = ImageClassification.labels([
      ImageLabel(identifier: "document", confidence: 0.4),
      ImageLabel(identifier: "food", confidence: 0.05),
      ImageLabel(identifier: "screenshot", confidence: 0.9),
      ImageLabel(identifier: "text", confidence: ClassificationRules.minimumLabelConfidence),
    ], minimumConfidence: ClassificationRules.minimumLabelConfidence)

    #expect(labels.map(\.identifier) == ["screenshot", "document", "text"])
  }

  @Test("넘겨받은 기준으로 거른다")
  func filtersByGivenMinimumConfidence() {
    let labels = ImageClassification.labels([
      ImageLabel(identifier: "food", confidence: 0.05),
      ImageLabel(identifier: "drink", confidence: 0.009),
      ImageLabel(identifier: "document", confidence: 0.4),
    ], minimumConfidence: 0.01)

    #expect(labels.map(\.identifier) == ["document", "food"])
  }

  @Test("신뢰도가 같으면 식별자 순으로 둔다")
  func breaksTiesByIdentifier() {
    let labels = ImageClassification.labels([
      ImageLabel(identifier: "pet", confidence: 0.5),
      ImageLabel(identifier: "dog", confidence: 0.5),
    ], minimumConfidence: ClassificationRules.minimumLabelConfidence)

    #expect(labels.map(\.identifier) == ["dog", "pet"])
  }

  @Test("취소된 Task 에서는 분석하지 않고 취소로 끝난다")
  func skipsClassificationWhenCancelled() async {
    let task = Task { () async -> Result<[ImageLabel], ImageAnalysisError> in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        let labels = try await ImageAnalysisClientImpl().classify(
          .stub(),
          minimumConfidence: ClassificationRules.minimumLabelConfidence
        )
        return .success(labels)
      } catch {
        return .failure(error)
      }
    }

    #expect(await task.value == .failure(.cancelled))
  }
}
