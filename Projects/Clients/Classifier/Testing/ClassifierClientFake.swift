import ClassifierInterface
import Core
import Synchronization

/// 테스트와 Example 앱용 대역. 정해 둔 답을 돌려주고, 모델까지 간 요청을 기록한다.
/// 실제 구현처럼 시작 전에 취소·쓸 수 있음을 확인하고, 끝난 뒤에 한 번 더 취소를 확인한다.
/// 쓸 수 있음을 실행 도중 바꾸고 요청을 기록해야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class ClassifierClientFake: ClassifierClient {
  private let classifyHandler: @Sendable ([RecognizedTextLine]) async -> Result<Set<ImageCategory>, ClassifierError>
  private let extractGifticonHandler: @Sendable ([RecognizedTextLine]) async
    -> Result<GifticonModelAnswer, ClassifierError>
  private let state: Mutex<State>

  private struct State {
    var isModelAvailable: Bool
    var requests: [ClassifierRequest] = []
  }

  /// 어떤 줄이든 같은 답을 돌려준다.
  public convenience init(
    isModelAvailable: Bool = true,
    classifyResult: Result<Set<ImageCategory>, ClassifierError> = .success([]),
    extractResult: Result<GifticonModelAnswer, ClassifierError> = .success(
      GifticonModelAnswer(expiryText: nil, redemptionPlace: nil)
    )
  ) {
    self.init(
      isModelAvailable: isModelAvailable,
      classify: { _ in classifyResult },
      extractGifticon: { _ in extractResult }
    )
  }

  /// 줄마다 다른 답. 기다리게 해 응답 도중 취소·쓸 수 있음 변화를 흉내 낸다.
  public init(
    isModelAvailable: Bool = true,
    classify: @escaping @Sendable ([RecognizedTextLine]) async -> Result<Set<ImageCategory>, ClassifierError>,
    extractGifticon: @escaping @Sendable ([RecognizedTextLine]) async -> Result<GifticonModelAnswer, ClassifierError>
  ) {
    self.classifyHandler = classify
    self.extractGifticonHandler = extractGifticon
    self.state = Mutex(State(isModelAvailable: isModelAvailable))
  }

  /// 모델을 쓸 수 있음 여부를 바꾼다. 기기 설정·모델 다운로드로 실행 도중 바뀌는 것을 흉내 낸다.
  public func setModelAvailable(_ isAvailable: Bool) {
    self.state.withLock { $0.isModelAvailable = isAvailable }
  }

  /// 모델까지 간 요청을 부른 순서대로. 부르기 전에 취소·쓸 수 없음으로 던진 요청과, 줄이 없어 빈 집합을 돌려준 `classify` 는 없다.
  /// 정해 둔 답이 오류인 요청은 있다.
  public var requests: [ClassifierRequest] {
    self.state.withLock { $0.requests }
  }

  public func isModelAvailable() -> Bool {
    self.state.withLock { $0.isModelAvailable }
  }

  /// 실제 구현처럼 정해 둔 답에서도 정보형 카테고리만 남긴다.
  public func classify(_ textLines: [RecognizedTextLine]) async throws(ClassifierError) -> Set<ImageCategory> {
    try self.checkBeforeRequest()
    if textLines.isEmpty {
      return []
    }
    let categories = try await self.perform(.classify(textLines)) { await self.classifyHandler(textLines) }
    return categories.filter { $0.group == .information }
  }

  public func extractGifticon(from textLines: [RecognizedTextLine]) async throws(ClassifierError)
    -> GifticonModelAnswer
  {
    try self.checkBeforeRequest()
    return try await self.perform(.extractGifticon(textLines)) { await self.extractGifticonHandler(textLines) }
  }

  /// 실제 구현처럼 모델을 부르기 전에 취소, 그다음 쓸 수 있음을 확인한다.
  private func checkBeforeRequest() throws(ClassifierError) {
    if Task.isCancelled {
      throw .cancelled
    }
    if !self.isModelAvailable() {
      throw .unavailable
    }
  }

  /// 요청을 기록하고 답을 기다린다. 답을 받은 뒤 Task 가 취소됐으면 답 대신 취소를 던진다(기다리는 도중에 끊지는 않는다).
  private func perform<Output>(
    _ request: ClassifierRequest,
    _ handler: () async -> Result<Output, ClassifierError>
  ) async throws(ClassifierError) -> Output {
    self.state.withLock { $0.requests.append(request) }
    let result = await handler()
    if Task.isCancelled {
      throw .cancelled
    }
    return try result.get()
  }
}

/// 모델까지 간 요청 한 건.
public enum ClassifierRequest: Sendable, Equatable {
  case classify([RecognizedTextLine])
  case extractGifticon([RecognizedTextLine])
}
