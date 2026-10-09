import ImageAnalysisInterface
import Vision

/// Vision 요청 실패를 Interface 의 이유로 바꾸는 규칙. 이미지 분류와 OCR 이 함께 쓴다.
enum VisionFailure {
  /// Task 가 취소된 뒤의 오류는 원인과 관계없이 취소로 본다.
  static func analysisError(_ error: any Error, isTaskCancelled: Bool) -> ImageAnalysisError {
    if isTaskCancelled || error is CancellationError {
      return .cancelled
    }
    if case VisionError.requestCancelled = error {
      return .cancelled
    }
    return .failed
  }
}
