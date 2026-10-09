import Core
import ImageAnalysisInterface
import Testing
import Vision
@testable import ImageAnalysisImpl

struct ImageClassificationTests {
  @Test("기준 미만 라벨을 빼고 신뢰도 높은 순으로 정렬한다")
  func filtersAndSortsLabels() {
    let labels = ImageClassification.labels([
      ImageLabel(identifier: "document", confidence: 0.4),
      ImageLabel(identifier: "food", confidence: 0.05),
      ImageLabel(identifier: "screenshot", confidence: 0.9),
      ImageLabel(identifier: "text", confidence: ImageClassification.minimumConfidence),
    ])

    #expect(labels.map(\.identifier) == ["screenshot", "document", "text"])
  }

  @Test("신뢰도가 같으면 식별자 순으로 둔다")
  func breaksTiesByIdentifier() {
    let labels = ImageClassification.labels([
      ImageLabel(identifier: "pet", confidence: 0.5),
      ImageLabel(identifier: "dog", confidence: 0.5),
    ])

    #expect(labels.map(\.identifier) == ["dog", "pet"])
  }

  @Test("취소 오류나 취소된 Task 의 오류는 취소로, 그 밖은 실패로 본다")
  func mapsAnalysisError() {
    struct Case {
      let error: any Error
      let isTaskCancelled: Bool
      let expected: ImageAnalysisError
    }
    let cases = [
      Case(error: CancellationError(), isTaskCancelled: false, expected: .cancelled),
      Case(error: VisionError.requestCancelled("cancelled"), isTaskCancelled: false, expected: .cancelled),
      Case(error: VisionError.invalidImage("invalid"), isTaskCancelled: true, expected: .cancelled),
      Case(error: VisionError.invalidImage("invalid"), isTaskCancelled: false, expected: .failed),
      Case(error: VisionError.internalError("internal"), isTaskCancelled: false, expected: .failed),
    ]

    for testCase in cases {
      #expect(
        ImageClassification.analysisError(testCase.error, isTaskCancelled: testCase.isTaskCancelled)
          == testCase.expected
      )
    }
  }

  @Test("취소된 Task 에서는 분석하지 않고 취소로 끝난다")
  func skipsClassificationWhenCancelled() async {
    let task = Task { () async -> Result<[ImageLabel], ImageAnalysisError> in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        let labels = try await ImageAnalysisClientImpl().classify(.stub())
        return .success(labels)
      } catch {
        return .failure(error)
      }
    }

    #expect(await task.value == .failure(.cancelled))
  }
}
