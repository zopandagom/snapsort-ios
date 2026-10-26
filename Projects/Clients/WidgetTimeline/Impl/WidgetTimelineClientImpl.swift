import Core
import WidgetKit
import WidgetTimelineInterface

/// `WidgetCenter` 구현. 위젯 kind 는 위젯 설정과 같은 Core 상수를 쓴다.
public struct WidgetTimelineClientImpl: WidgetTimelineClient {
  public init() {}

  public func reloadExpiryWidget() {
    WidgetCenter.shared.reloadTimelines(ofKind: ExpiryWidgetTimeline.kind)
  }
}
