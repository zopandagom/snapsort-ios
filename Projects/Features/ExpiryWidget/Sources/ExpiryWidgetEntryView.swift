import Core
import DesignSystem
import SwiftUI
import WidgetKit

/// 만료 임박 위젯 화면. entry 값만 그린다. 잠금 화면에도 보이므로 개수·D-day·상태 문구만 쓴다(교환처·썸네일 없음).
/// 크기는 인자로 받는다(`\.widgetFamily` 는 앱에서 정할 수 없어 Example 이 크기별로 그릴 수 없다).
public struct ExpiryWidgetEntryView: View {
  private let entry: ExpiryWidgetEntry
  private let family: WidgetFamily

  public init(entry: ExpiryWidgetEntry, family: WidgetFamily) {
    self.entry = entry
    self.family = family
  }

  public var body: some View {
    self.content
      .fontDesign(.rounded)
  }

  @ViewBuilder
  private var content: some View {
    switch self.family {
    case .accessoryCircular:
      CircularView(content: self.entry.content)
        .containerBackground(for: .widget) { Color.clear }
    case .accessoryRectangular:
      RectangularView(content: self.entry.content)
        .containerBackground(for: .widget) { Color.clear }
    default:
      SmallView(content: self.entry.content)
        .containerBackground(SnapColor.background, for: .widget)
    }
  }
}

private enum Copy {
  static let title = "만료 임박"
  static let unavailable = "앱을 열어 주세요"
  static let none = "7일 안에 만료되는 기프티콘이 없어요"
  static let checking = "확인 중"

  /// 가장 가까운 만료. 오늘 만료는 "오늘 만료", 남으면 "가장 가까운 D-3".
  static func nearest(_ daysLeft: Int) -> String {
    daysLeft == 0 ? "오늘 만료" : "가장 가까운 D-\(daysLeft)"
  }
}

/// 선물 아이콘. 색을 쓰는 홈 화면(fullColor)에서만 시안 색이고, tinted·clear·잠금 화면에서는 단색이다.
/// 그림은 고유 크기가 없어 Label 안에서 늘어나지 않게 크기를 정한다(큰 글씨를 따라 커진다).
private struct GiftIcon: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  @ScaledMetric private var size: CGFloat

  init(size: CGFloat, relativeTo textStyle: Font.TextStyle) {
    self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
  }

  var body: some View {
    SnapIcon(.gift, style: self.renderingMode == .fullColor ? .color : .monochrome)
      .frame(width: self.size, height: self.size)
  }
}

private struct SmallView: View {
  let content: ExpiryWidgetEntry.Content

  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label {
        Text(Copy.title)
      } icon: {
        GiftIcon(size: 14, relativeTo: .caption)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      switch self.content {
      case .unavailable:
        Text(Copy.unavailable)
          .font(.headline)
      case let .summary(summary):
        if let nearest = summary.nearestDaysLeft {
          // 숫자만 크게 두면 남은 날로 읽힐 수 있어 "개"를 붙인다.
          Text("\(summary.count)개")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            // 아래 본문 글자처럼 색을 쓰는 홈 화면에서만 기준값 색을 쓴다(vibrant 에서 밝기가 불투명도로 바뀌어 흐려지지 않게).
            .foregroundStyle(self
              .renderingMode == .fullColor ? AnyShapeStyle(SnapColor.accent) : AnyShapeStyle(.primary))
            .widgetAccentable()
          Text(Copy.nearest(nearest))
            .font(.subheadline)
        } else if summary.isChecking {
          Text(Copy.checking)
            .font(.headline)
        } else {
          Text(Copy.none)
            .font(.subheadline)
        }
        if summary.isChecking, summary.nearestDaysLeft != nil {
          Text(Copy.checking)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    // 색을 쓰는 홈 화면에서만 기준값 글자색을 쓴다. 나머지 모드는 시스템이 단색으로 칠한다.
    .foregroundStyle(
      self.renderingMode == .fullColor ? AnyShapeStyle(SnapColor.ink) : AnyShapeStyle(.primary),
      self.renderingMode == .fullColor ? AnyShapeStyle(SnapColor.inkSecondary) : AnyShapeStyle(.secondary)
    )
  }
}

private struct CircularView: View {
  let content: ExpiryWidgetEntry.Content

  var body: some View {
    ZStack {
      AccessoryWidgetBackground()
      VStack(spacing: 0) {
        switch self.content {
        case .unavailable:
          GiftIcon(size: 18, relativeTo: .body)
          Text("앱 열기")
            .font(.system(size: 9))
        case let .summary(summary):
          Text("\(summary.count)")
            .font(.title3.weight(.bold))
            .widgetAccentable()
          // 칸이 좁아 D-day 는 넣지 않는다. 숫자 아래에 추출 대기면 "확인 중"(개수가 바뀔 수 있다), 아니면 1개 이상은 "개"·0개는 선물 아이콘.
          if summary.isChecking {
            Text(Copy.checking)
              .font(.system(size: 9))
          } else if summary.nearestDaysLeft != nil {
            Text("개")
              .font(.system(size: 10))
          } else {
            GiftIcon(size: 12, relativeTo: .caption2)
          }
        }
      }
    }
  }
}

private struct RectangularView: View {
  let content: ExpiryWidgetEntry.Content

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Label {
        Text(Copy.title)
      } icon: {
        GiftIcon(size: 17, relativeTo: .headline)
      }
      .font(.headline)
      .widgetAccentable()
      switch self.content {
      case .unavailable:
        Text(Copy.unavailable)
      case let .summary(summary):
        if let nearest = summary.nearestDaysLeft {
          Text("\(summary.count)개 · \(Copy.nearest(nearest))")
        } else if !summary.isChecking {
          Text("7일 안에 없어요")
        }
        if summary.isChecking {
          Text(Copy.checking)
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.caption)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
