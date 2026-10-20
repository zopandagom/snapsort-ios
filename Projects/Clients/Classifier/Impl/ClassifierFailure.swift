import ClassifierInterface

/// 모델 요청 실패를 Interface 의 이유로 바꾸는 규칙.
/// 오류 종류(`GenerationError`·`LanguageModelError`·`NSError`)로 나누지 않는다. SDK 버전마다 타입이 다르고,
/// 같은 상황(응답 도중 취소)도 기기마다 다른 오류로 온다. 원인 오류에는 OCR 텍스트가 섞일 수 있어 남기지 않는다.
enum ClassifierFailure {
  /// Task 가 취소됐을 때만 취소로 본다(Mac 은 응답 도중 취소를 `decodingFailure` 로 준다).
  /// Task 가 취소되지 않았는데 온 `CancellationError` 는 실패다. 취소로 바꾸면 받는 쪽이 실행을 멈추고,
  /// 같은 입력에서 반복되면 다시 시도할 때마다 멈춘다.
  /// 오류 뒤 모델을 쓸 수 없으면(요청 도중 쓸 수 없게 됨) 실패로 세지 않도록 쓸 수 없음으로 본다.
  static func error(_ error: any Error, isTaskCancelled: Bool, isModelAvailable: Bool) -> ClassifierError {
    if isTaskCancelled {
      return .cancelled
    }
    if !isModelAvailable {
      return .unavailable
    }
    return .failed
  }
}
