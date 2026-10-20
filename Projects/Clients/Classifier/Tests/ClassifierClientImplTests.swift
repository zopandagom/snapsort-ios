import ClassifierInterface
import Core
import Foundation
import FoundationModels
import Testing
@testable import ClassifierImpl

/// 실제 모델을 부르지 않는다. `make test` 의 시뮬레이터는 모델을 쓸 수 있다고 답하지만 요청이 모두 실패한다
/// (docs/CONVENTIONS.md §3). 모델 답의 품질은 정확도 측정 작업에서 본다.
struct ClassifierClientImplTests {
  private struct ModelFailure: Error {}

  @Test("프롬프트는 줄 번호를 붙이고 글자 수 상한에서 자른다")
  func numbersAndTruncatesPrompt() {
    #expect(ClassifierPrompt.text([.line("스타벅스"), .line("유효기간 2026.12.31")])
      == "OCR 줄:\n1: 스타벅스\n2: 유효기간 2026.12.31")

    // "1: " 과 줄 사이 "\n" 까지 세어 정확히 상한인 두 줄은 넣고, 그 뒤 줄은 뺀다.
    let limit = ClassifierPrompt.maximumPromptCharacters
    let first = String(repeating: "가", count: limit / 2 - 3)
    let second = String(repeating: "나", count: limit / 2 - 4)
    #expect(ClassifierPrompt.text([.line(first), .line(second), .line("다")])
      == "OCR 줄:\n1: \(first)\n2: \(second)")
    #expect(ClassifierPrompt.text([.line(first), .line(second + "나")]) == "OCR 줄:\n1: \(first)")
    #expect(ClassifierPrompt.text([]) == nil)
  }

  @Test("보낼 줄이 없으면 프롬프트는 nil 이다")
  func returnsNilPromptWithoutLinesToSend() {
    let limit = ClassifierPrompt.maximumPromptCharacters
    #expect(ClassifierPrompt.text([]) == nil)
    // "1: " 을 붙이면 상한을 넘는 첫 줄만 있으면 보낼 줄이 없다.
    #expect(ClassifierPrompt.text([.line(String(repeating: "가", count: limit - 2)), .line("다")]) == nil)
    let exact = String(repeating: "가", count: limit - 3)
    #expect(ClassifierPrompt.text([.line(exact)]) == "OCR 줄:\n1: \(exact)")
  }

  @Test("모델 종류를 정보형 카테고리로 바꾸고 none 은 버린다")
  func mapsInformationKinds() {
    let pairs: [(InformationKind, ImageCategory?)] = [
      (.gifticon, .gifticon), (.receipt, .receipt), (.chat, .chat), (.shopping, .shopping),
      (.map, .map), (.document, .document), (.none, nil),
    ]
    for (kind, category) in pairs {
      #expect(kind.category == category, "\(kind)")
    }
    #expect(InformationKinds(kinds: [.receipt, .none]).categories == [.receipt])
    #expect(InformationKinds(kinds: [.none]).categories.isEmpty)
    #expect(InformationKinds(kinds: [.chat, .chat]).categories == [.chat])
  }

  @Test("공백뿐인 답은 nil 로 바꾼다")
  func trimsBlankAnswers() {
    #expect(GifticonFields(expiryDateText: " \n", redemptionPlace: " CU ").modelAnswer
      == GifticonModelAnswer(expiryText: nil, redemptionPlace: "CU"))
    #expect(GifticonFields(expiryDateText: "2026.12.31 ", redemptionPlace: nil).modelAnswer
      == GifticonModelAnswer(expiryText: "2026.12.31", redemptionPlace: nil))
    #expect(GifticonFields(expiryDateText: "", redemptionPlace: "").modelAnswer
      == GifticonModelAnswer(expiryText: nil, redemptionPlace: nil))
  }

  @Test("취소된 Task 의 오류는 cancelled 다(응답 도중 취소가 디코딩 실패로 와도)")
  func mapsErrorAfterTaskCancelledToCancelled() {
    for error: any Error in [ModelFailure(), CancellationError()] {
      for isModelAvailable in [true, false] {
        #expect(
          ClassifierFailure.error(error, isTaskCancelled: true, isModelAvailable: isModelAvailable) == .cancelled
        )
      }
    }
  }

  @Test("Task 가 취소되지 않았으면 CancellationError 도 취소가 아니다")
  func mapsCancellationErrorWithoutTaskCancelToRejected() {
    // 종류를 알 수 없는 오류와 같다. 취소로 바꾸면 인덱서가 실행을 멈춘다.
    #expect(ClassifierFailure.error(CancellationError(), isTaskCancelled: false, isModelAvailable: true) == .rejected)
  }

  @Test("오류 뒤 모델을 쓸 수 없으면 unavailable 이다")
  func mapsErrorWhileModelUnavailableToUnavailable() {
    for error: any Error in [ModelFailure(), CancellationError()] {
      #expect(ClassifierFailure.error(error, isTaskCancelled: false, isModelAvailable: false) == .unavailable)
    }
  }

  @Test("입력 때문인 오류는 failed 다")
  func mapsInputErrorsToFailed() {
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "")
    var errors: [any Error] = [
      LanguageModelSession.GenerationError.exceededContextWindowSize(context),
      LanguageModelSession.GenerationError.guardrailViolation(context),
      LanguageModelSession.GenerationError.refusal(.init(transcriptEntries: []), context),
      LanguageModelSession.GenerationError.decodingFailure(context),
    ]
    if #available(iOS 27.0, *) {
      errors += [
        LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "")),
        LanguageModelError.guardrailViolation(.init(debugDescription: "")),
        LanguageModelError.refusal(.init(explanation: "", debugDescription: "")),
        GeneratedContent.ParsingError(rawContent: "", debugDescription: ""),
      ]
    }
    for error in errors {
      #expect(ClassifierFailure.reason(of: error) == .input, "\(error)")
      #expect(ClassifierFailure.error(error, isTaskCancelled: false, isModelAvailable: true) == .failed, "\(error)")
    }
  }

  @Test("입력과 관계없는 시스템 거부는 rejected 다")
  func mapsSystemErrorsToRejected() {
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "")
    var errors: [any Error] = [
      LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context),
      LanguageModelSession.GenerationError.rateLimited(context),
      LanguageModelSession.GenerationError.concurrentRequests(context),
      LanguageModelSession.GenerationError.unsupportedGuide(context),
    ]
    if #available(iOS 27.0, *) {
      errors += [
        LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .korean, debugDescription: "")),
        LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "")),
        LanguageModelError.timeout(.init(debugDescription: "")),
        LanguageModelError.unsupportedCapability(.init(capability: .vision, debugDescription: "")),
        LanguageModelError.unsupportedTranscriptContent(.init(unsupportedContent: [], debugDescription: "")),
        LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil, debugDescription: "")),
        LanguageModelSession.Error.concurrentRequests,
        LanguageModelSession.Error.transcriptMutationWhileResponding,
      ]
    }
    for error in errors {
      #expect(ClassifierFailure.reason(of: error) == .system, "\(error)")
      #expect(ClassifierFailure.error(error, isTaskCancelled: false, isModelAvailable: true) == .rejected, "\(error)")
    }
  }

  @Test("모델 자산이 없다는 오류는 unavailable 다")
  func mapsAssetsUnavailableToUnavailable() {
    var errors: [any Error] = [
      LanguageModelSession.GenerationError.assetsUnavailable(.init(debugDescription: "")),
    ]
    if #available(iOS 27.0, *) {
      errors.append(SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "")))
    }
    for error in errors {
      #expect(ClassifierFailure.reason(of: error) == .unavailable, "\(error)")
      // 요청 뒤 `isModelAvailable()` 이 아직 참이어도 쓸 수 없음이다.
      #expect(
        ClassifierFailure.error(error, isTaskCancelled: false, isModelAvailable: true) == .unavailable,
        "\(error)"
      )
    }
  }

  @Test("종류를 알 수 없는 오류는 rejected 다(시뮬레이터의 NSError)")
  func mapsUnknownErrorsToRejected() {
    let errors: [any Error] = [
      NSError(domain: "FoundationModels.LanguageModelError", code: -1),
      ModelFailure(),
    ]
    for error in errors {
      #expect(ClassifierFailure.reason(of: error) == .system, "\(error)")
      #expect(ClassifierFailure.error(error, isTaskCancelled: false, isModelAvailable: true) == .rejected, "\(error)")
    }
  }
}
