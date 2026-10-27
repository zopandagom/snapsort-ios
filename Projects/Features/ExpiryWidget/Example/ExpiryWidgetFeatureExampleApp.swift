import Core
import DesignSystem
import ExpiryWidgetFeature
import SwiftUI
import WidgetKit

/// 위젯을 홈 화면에 놓지 않고 크기 3종 × 상태 5개를 한 화면에서 확인하는 데모 앱. Preview 도 여기에 둔다.
/// 상태는 정적 entry 로 그린다(저장소를 읽어 상태를 정하는 것은 Provider 테스트가 본다).
@main
struct ExpiryWidgetFeatureExampleApp: App {
  var body: some Scene {
    WindowGroup {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          ForEach(PreviewEntries.all, id: \.title) { state in
            StateRow(title: state.title, entry: state.entry)
          }
        }
        .padding()
      }
      .snapTheme()
    }
  }
}

/// 한 상태를 크기 3종으로 그린다. 크기는 기기 위젯 크기의 근사값이다.
private struct StateRow: View {
  let title: String
  let entry: ExpiryWidgetEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(self.title)
        .font(.headline)
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 12) {
          WidgetFrame(entry: self.entry, family: .systemSmall, size: CGSize(width: 170, height: 170))
          WidgetFrame(entry: self.entry, family: .accessoryCircular, size: CGSize(width: 76, height: 76))
          WidgetFrame(entry: self.entry, family: .accessoryRectangular, size: CGSize(width: 172, height: 76))
        }
      }
    }
  }
}

private struct WidgetFrame: View {
  let entry: ExpiryWidgetEntry
  let family: WidgetFamily
  let size: CGSize

  var body: some View {
    ExpiryWidgetEntryView(entry: self.entry, family: self.family)
      .padding(self.family == .systemSmall ? 16 : 4)
      .frame(width: self.size.width, height: self.size.height)
      // 앱 안에서는 `containerBackground` 가 그려지지 않아 위젯 바탕을 흉내 낸다(작은 위젯은 `SnapColor.background`).
      .background(
        self
          .family == .systemSmall ? AnyShapeStyle(SnapColor.background) :
          AnyShapeStyle(Color(.secondarySystemBackground)),
        in: .rect(cornerRadius: self.family == .systemSmall ? 22 : 12)
      )
  }
}

private enum PreviewEntries {
  struct State {
    let title: String
    let entry: ExpiryWidgetEntry
  }

  static let all = [
    State(title: "앱을 열어 주세요", entry: ExpiryWidgetEntry(date: .now, content: .unavailable)),
    State(title: "없음", entry: Self.summary(count: 0, nearest: nil, isChecking: false)),
    State(title: "임박", entry: Self.summary(count: 3, nearest: 0, isChecking: false)),
    State(title: "임박 + 확인 중", entry: Self.summary(count: 2, nearest: 5, isChecking: true)),
    State(title: "0개 + 확인 중", entry: Self.summary(count: 0, nearest: nil, isChecking: true)),
  ]

  static func summary(count: Int, nearest: Int?, isChecking: Bool) -> ExpiryWidgetEntry {
    ExpiryWidgetEntry(
      date: .now,
      content: .summary(ExpiryWidgetSummary(
        date: LocalDate(.now, calendar: .autoupdatingCurrent),
        count: count,
        nearestDaysLeft: nearest,
        isChecking: isChecking
      ))
    )
  }
}

#Preview("크기 3종 × 상태") {
  ScrollView {
    VStack(alignment: .leading, spacing: 24) {
      ForEach(PreviewEntries.all, id: \.title) { state in
        StateRow(title: state.title, entry: state.entry)
      }
    }
    .padding()
  }
}
