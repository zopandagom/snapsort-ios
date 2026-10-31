import BackgroundIndexingInterface

/// 테스트와 Example 앱용 대역. BG 작업을 하지 않고 받은 이벤트를 순서대로 기록한다.
/// 계속 처리 분류 상태와 요청 결과는 테스트가 정한다(`continuedIndexingState`, `continuedRequestResult`).
/// 기록이 호출 사이에 남아야 하는 class 이고, 이벤트가 MainActor 에서만 오므로 상태도 MainActor 에 둔다.
@MainActor
public final class BackgroundIndexingClientFake: BackgroundIndexingClient {
  public enum Event: Sendable, Equatable {
    case didEnterBackground
    case didBecomeActive
    case continuedIndexingRequested
  }

  /// 받은 이벤트를 부른 순서대로.
  public private(set) var events: [Event] = []
  /// 계속 처리 분류 상태. 요청 결과가 `.started` 면 `.active`, `.unavailable` 이면 `.unsupported` 로 바뀐다.
  public var continuedIndexingState: ContinuedIndexingState
  /// `requestContinuedIndexing(text:)` 가 돌려줄 값.
  public var continuedRequestResult: ContinuedIndexingRequestResult
  /// 마지막 요청에 넘긴 문구.
  public private(set) var lastContinuedText: ContinuedIndexingText?

  public init(
    continuedIndexingState: ContinuedIndexingState = .idle,
    continuedRequestResult: ContinuedIndexingRequestResult = .started
  ) {
    self.continuedIndexingState = continuedIndexingState
    self.continuedRequestResult = continuedRequestResult
  }

  public func appDidEnterBackground() {
    self.events.append(.didEnterBackground)
  }

  public func appDidBecomeActive() {
    self.events.append(.didBecomeActive)
  }

  public func requestContinuedIndexing(text: ContinuedIndexingText) -> ContinuedIndexingRequestResult {
    self.events.append(.continuedIndexingRequested)
    self.lastContinuedText = text
    switch self.continuedRequestResult {
    case .started:
      self.continuedIndexingState = .active
    case .unavailable:
      self.continuedIndexingState = .unsupported
    case .temporarilyUnavailable:
      break
    }
    return self.continuedRequestResult
  }
}
