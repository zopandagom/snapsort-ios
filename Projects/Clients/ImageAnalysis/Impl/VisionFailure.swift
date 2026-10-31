import ImageAnalysisInterface
import Vision

/// Vision 요청 실패를 Interface 의 이유로 바꾸는 규칙. 이미지 분류·OCR·바코드 인식·특징 벡터가 함께 쓴다.
enum VisionFailure {
  /// 세션 요청(분류·벡터)이 실패했을 때 할 일.
  enum SessionReaction: Equatable {
    /// 취소. 세대는 그대로 둔다.
    case cancelled
    /// 큐 시한 초과. 큐 훅이 이미 세대를 버리고 로그를 남겼으므로 `.failed` 만 던진다.
    case timedOut
    /// 버린 큐라 돌지 않았다. 그 세대를 버리고 새로 체크아웃해 한 번 다시 부른다.
    case retry
    /// 실패. `discards` 면 그 세대를 버리고 실패 로그를 남긴다.
    case failed(discards: Bool)
  }

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

  /// 취소가 먼저다. 버린 큐(`.abandoned`)는 처음이면 다시 부르고, 다시 부른 것에서 또 오면(새 세대도 시한으로 버려짐) 버리지 않고 실패다.
  static func sessionReaction(_ error: any Error, isTaskCancelled: Bool, isRetry: Bool) -> SessionReaction {
    if self.analysisError(error, isTaskCancelled: isTaskCancelled) == .cancelled {
      return .cancelled
    }
    switch error as? VisionWorkQueue.Failure {
    case .timedOut:
      return .timedOut
    case .abandoned:
      return isRetry ? .failed(discards: false) : .retry
    case nil:
      return .failed(discards: true)
    }
  }
}
