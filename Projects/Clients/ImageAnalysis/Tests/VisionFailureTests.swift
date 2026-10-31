import Foundation
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

  @Test("세션 큐가 취소로 돌아오면(CancellationError) 실패가 아니라 취소다. 세션 요청은 취소면 세션을 버리지 않는다")
  func sessionCancellationIsNotFailure() {
    #expect(VisionFailure.analysisError(CancellationError(), isTaskCancelled: false) == .cancelled)
    #expect(VisionFailure.analysisError(CancellationError(), isTaskCancelled: true) == .cancelled)
    #expect(VisionFailure.analysisError(ImageAnalysisError.failed, isTaskCancelled: false) == .failed)
  }

  @Test("세션 요청 실패: 취소가 먼저이고, 시한 초과는 실패, 버린 큐는 처음만 다시 부르며, 그 밖은 세대를 버리는 실패다")
  func mapsSessionReaction() {
    struct Case {
      let error: any Error
      let isTaskCancelled: Bool
      let isRetry: Bool
      let expected: VisionFailure.SessionReaction
    }
    let failure = NSError(domain: "test", code: 1)
    let cases = [
      Case(error: CancellationError(), isTaskCancelled: false, isRetry: false, expected: .cancelled),
      Case(error: VisionWorkQueue.Failure.timedOut, isTaskCancelled: true, isRetry: false, expected: .cancelled),
      Case(error: VisionWorkQueue.Failure.abandoned, isTaskCancelled: true, isRetry: false, expected: .cancelled),
      Case(error: failure, isTaskCancelled: true, isRetry: true, expected: .cancelled),
      Case(error: VisionWorkQueue.Failure.timedOut, isTaskCancelled: false, isRetry: false, expected: .timedOut),
      Case(error: VisionWorkQueue.Failure.timedOut, isTaskCancelled: false, isRetry: true, expected: .timedOut),
      Case(error: VisionWorkQueue.Failure.abandoned, isTaskCancelled: false, isRetry: false, expected: .retry),
      Case(
        error: VisionWorkQueue.Failure.abandoned,
        isTaskCancelled: false,
        isRetry: true,
        expected: .failed(discards: false)
      ),
      Case(error: failure, isTaskCancelled: false, isRetry: false, expected: .failed(discards: true)),
      Case(error: ImageAnalysisError.failed, isTaskCancelled: false, isRetry: true, expected: .failed(discards: true)),
    ]

    for testCase in cases {
      #expect(
        VisionFailure.sessionReaction(
          testCase.error,
          isTaskCancelled: testCase.isTaskCancelled,
          isRetry: testCase.isRetry
        ) == testCase.expected
      )
    }
  }
}
