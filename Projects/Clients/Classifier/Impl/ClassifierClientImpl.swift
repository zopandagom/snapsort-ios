import ClassifierInterface
import Core
import FoundationModels

/// Foundation Models 기반 구현. 온디바이스 `SystemLanguageModel.default` 만 쓴다(Private Cloud Compute 는 lint 가 막는다).
/// 상태가 없고 요청마다 새 세션을 만든다. 세션을 다시 쓰면 transcript 가 쌓여 문맥(4,096 토큰)을 넘고,
/// 앞 이미지의 지시문이 다음 이미지 답에 섞인다. 세션 하나에 요청 하나라 동시 요청 오류도 생기지 않는다.
/// 사진에서 읽은 텍스트와 모델 답은 로그에 남기지 않는다.
public struct ClassifierClientImpl: ClassifierClient {
  /// 탐욕 샘플링으로 같은 줄에서 같은 답을 얻는다. 답은 짧은 필드라 응답 토큰을 묶는다(임시 값).
  /// 기프티콘 요청도 쓰므로, 바꿔서 같은 줄에서 다른 기프티콘 답이 나올 수 있으면 `GifticonExtractor.modelFillVersion` 을 올린다.
  private static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256)

  public init() {}

  public func isModelAvailable() -> Bool {
    SystemLanguageModel.default.availability == .available
  }

  /// 모델 실행이 메인 스레드를 막지 않도록 메인 밖에서 실행한다.
  @concurrent
  public func classify(_ textLines: [RecognizedTextLine]) async throws(ClassifierError) -> Set<ImageCategory> {
    try self.checkBeforeRequest()
    if textLines.isEmpty {
      return []
    }
    let answer = try await self.respond(
      instructions: ClassifierPrompt.classifyInstructions,
      textLines: textLines,
      generating: InformationKinds.self
    )
    return answer.categories
  }

  @concurrent
  public func extractGifticon(from textLines: [RecognizedTextLine]) async throws(ClassifierError)
    -> GifticonModelAnswer
  {
    try self.checkBeforeRequest()
    if textLines.isEmpty {
      return GifticonModelAnswer(expiryText: nil, redemptionPlace: nil)
    }
    let answer = try await self.respond(
      instructions: ClassifierPrompt.gifticonInstructions,
      textLines: textLines,
      generating: GifticonFields.self
    )
    return answer.modelAnswer
  }

  private func checkBeforeRequest() throws(ClassifierError) {
    if Task.isCancelled {
      throw .cancelled
    }
    if !self.isModelAvailable() {
      throw .unavailable
    }
  }

  /// 새 세션으로 한 번 묻고 실패를 이유로 바꾼다. 끝난 뒤에 Task 취소를 한 번 더 확인한다.
  private func respond<Content: Generable>(
    instructions: String,
    textLines: [RecognizedTextLine],
    generating type: Content.Type
  ) async throws(ClassifierError) -> Content {
    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
    let content: Content
    do {
      content = try await session.respond(
        to: ClassifierPrompt.text(textLines),
        generating: type,
        options: Self.options
      ).content
    } catch {
      throw ClassifierFailure.error(error, isTaskCancelled: Task.isCancelled, isModelAvailable: self.isModelAvailable())
    }
    // 응답 중에 취소돼도 답이 올 수 있으므로 한 번 더 확인한다.
    if Task.isCancelled {
      throw .cancelled
    }
    return content
  }
}
