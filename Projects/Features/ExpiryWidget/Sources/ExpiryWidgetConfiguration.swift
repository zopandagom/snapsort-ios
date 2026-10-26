import Core
import SwiftUI
import WidgetKit

/// 만료 임박 위젯의 구성. `Widget` 구조체는 인자 없는 `init()` 이 필요해 조립 지점(Extension)에 두고,
/// 그 `body` 가 Impl 로 만든 Provider 를 넘겨 이것을 돌려준다.
public enum ExpiryWidgetConfiguration {
  @MainActor
  public static func make(provider: ExpiryWidgetProvider) -> some WidgetConfiguration {
    StaticConfiguration(kind: ExpiryWidgetTimeline.kind, provider: provider) { entry in
      FamilyReadingView(entry: entry)
    }
    .configurationDisplayName("만료 임박 기프티콘")
    .description("7일 안에 만료되는 기프티콘 수와 가장 가까운 D-day")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
  }
}

/// 위젯에서는 크기를 환경 값으로 읽어 넘긴다.
private struct FamilyReadingView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ExpiryWidgetEntry

  var body: some View {
    ExpiryWidgetEntryView(entry: self.entry, family: self.family)
  }
}
