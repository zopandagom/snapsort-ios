import Synchronization
import WidgetTimelineInterface

/// 테스트와 Example 앱용 대역. 위젯에 요청하지 않고 호출 수를 기록한다.
/// 기록이 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class WidgetTimelineClientFake: WidgetTimelineClient {
  private let state = Mutex(0)

  public init() {}

  /// `reloadExpiryWidget` 을 부른 횟수.
  public var reloadCount: Int {
    self.state.withLock { $0 }
  }

  public func reloadExpiryWidget() {
    self.state.withLock { $0 += 1 }
  }
}
