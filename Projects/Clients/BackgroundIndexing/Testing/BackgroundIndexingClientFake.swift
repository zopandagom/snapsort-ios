import BackgroundIndexingInterface

/// 테스트와 Example 앱용 대역. BG 작업을 하지 않고 받은 이벤트를 순서대로 기록한다.
/// 기록이 호출 사이에 남아야 하는 class 이고, 이벤트가 MainActor 에서만 오므로 상태도 MainActor 에 둔다.
@MainActor
public final class BackgroundIndexingClientFake: BackgroundIndexingClient {
  public enum Event: Sendable, Equatable {
    case didEnterBackground
    case didBecomeActive
  }

  /// 받은 이벤트를 부른 순서대로.
  public private(set) var events: [Event] = []

  public init() {}

  public func appDidEnterBackground() {
    self.events.append(.didEnterBackground)
  }

  public func appDidBecomeActive() {
    self.events.append(.didBecomeActive)
  }
}
