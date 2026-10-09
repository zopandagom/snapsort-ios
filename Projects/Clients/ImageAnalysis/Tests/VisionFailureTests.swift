import ImageAnalysisInterface
import Testing
import Vision
@testable import ImageAnalysisImpl

struct VisionFailureTests {
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
        VisionFailure.analysisError(testCase.error, isTaskCancelled: testCase.isTaskCancelled)
          == testCase.expected
      )
    }
  }
}
