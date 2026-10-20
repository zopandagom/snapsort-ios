import ClassifierInterface
import FoundationModels

/// 모델 요청 실패를 Interface 의 이유로 바꾸는 규칙.
/// 오류 종류를 입력 탓(같은 입력이면 반복된다), 시스템 거부(입력과 관계없음), 쓸 수 없음으로 나눈다.
/// 입력 탓만 그 이미지의 실패로 센다. 입력 탓인지 알 수 없는 오류(시뮬레이터의 `NSError` 등)는 시스템 거부로 본다.
/// 실패로 세면 행이 보강을 마친 것으로 굳어 다시 묻지 않으므로, 모르면 굳히지 않는다.
/// iOS 27 SDK 는 iOS 26 의 `GenerationError` 를 deprecated 하고 새 타입으로 나눴으므로 새 타입을 먼저 본다.
/// 새 타입은 iOS 27 SDK(Swift 6.4 컴파일러)에만 있어 `#if compiler(>=6.4)` 로 감싼다. iOS 26 SDK 로 빌드하면(CI)
/// iOS 27 기기의 새 타입 오류는 종류를 알 수 없는 오류(시스템 거부)가 된다.
/// 원인 오류에는 OCR 텍스트가 섞일 수 있어 남기지 않는다.
enum ClassifierFailure {
  enum Reason: Equatable {
    /// 이 입력 때문이다(문맥 초과·가드레일·거절·형식 불일치).
    case input
    /// 입력과 관계없이 시스템이 받지 않았다.
    case system
    /// 모델 자산이 없다.
    case unavailable
  }

  /// Task 가 취소됐을 때만 취소로 본다(Mac 은 응답 도중 취소를 `decodingFailure` 로 준다).
  /// Task 가 취소되지 않았는데 온 `CancellationError` 는 종류를 알 수 없는 오류다. 취소로 바꾸면 받는 쪽이 실행을 멈추고,
  /// 같은 입력에서 반복되면 다시 시도할 때마다 멈춘다.
  /// 오류 뒤 모델을 쓸 수 없으면(요청 도중 쓸 수 없게 됨) 실패로 세지 않도록 쓸 수 없음으로 본다.
  static func error(_ error: any Error, isTaskCancelled: Bool, isModelAvailable: Bool) -> ClassifierError {
    if isTaskCancelled {
      return .cancelled
    }
    if !isModelAvailable {
      return .unavailable
    }
    switch self.reason(of: error) {
    case .input: return .failed
    case .system: return .rejected
    case .unavailable: return .unavailable
    }
  }

  static func reason(of error: any Error) -> Reason {
    #if compiler(>=6.4)
      if #available(iOS 27.0, *) {
        if let reason = self.reasonOfCurrentError(error) {
          return reason
        }
      }
    #endif
    guard let error = error as? LanguageModelSession.GenerationError else {
      return .system
    }
    switch error {
    case .exceededContextWindowSize, .guardrailViolation, .refusal, .decodingFailure:
      return .input
    case .assetsUnavailable:
      return .unavailable
    // 미지원 언어는 입력 언어 탓인지 기기 언어 설정 탓인지 알 수 없다.
    case .unsupportedLanguageOrLocale, .rateLimited, .concurrentRequests, .unsupportedGuide:
      return .system
    @unknown default:
      return .system
    }
  }

  #if compiler(>=6.4)
    /// iOS 27 SDK 의 오류 타입. 그 타입이 아니면 nil.
    @available(iOS 27.0, *)
    private static func reasonOfCurrentError(_ error: any Error) -> Reason? {
      if let error = error as? LanguageModelError {
        switch error {
        case .contextSizeExceeded, .guardrailViolation, .refusal:
          return .input
        // 입력은 글자 수 상한 안이므로 시간 초과·형식 정의 문제는 입력과 관계없다.
        case .unsupportedLanguageOrLocale, .rateLimited, .timeout, .unsupportedCapability,
             .unsupportedTranscriptContent,
             .unsupportedGenerationGuide:
          return .system
        @unknown default:
          return .system
        }
      }
      if error is GeneratedContent.ParsingError {
        return .input
      }
      if error is SystemLanguageModel.Error {
        return .unavailable
      }
      if error is LanguageModelSession.Error {
        return .system
      }
      return nil
    }
  #endif
}
