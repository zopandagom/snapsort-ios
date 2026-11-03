import SwiftUI

/// 목록 위 탭 컨트롤. 시스템 segmented Picker 대신 쓴다. 선택 표시가 누른 탭으로 미끄러지고, 탭마다 개수를 붙일 수 있다(바뀌면 굴러간다).
/// VoiceOver 는 탭 막대로 읽고 탭마다 "제목, n개"와 선택 상태를 읽는다.
/// 동작 줄이기(Reduce Motion)면 선택 표시는 바로 옮기고, 선택이 바뀌는 것은 짧은 투명도 전환으로 한다(목록 전환 같은 바깥 애니메이션에 쓰인다).
/// 높이는 Dynamic Type 을 따르고 탭마다 누를 수 있는 높이는 44pt 이상이다.
public struct SnapSegmentedTabs<Value: Hashable>: View {
  public struct Tab {
    public let value: Value
    public let title: String
    /// 탭 옆 개수. nil 이면 개수를 보이지 않는다(불러오는 중·실패).
    public let count: Int?

    public init(_ value: Value, _ title: String, count: Int?) {
      self.value = value
      self.title = title
      self.count = count
    }
  }

  /// 선택 표시가 미끄러지는 애니메이션.
  public static var animation: Animation {
    .spring(response: 0.35, dampingFraction: 0.75)
  }

  /// 동작 줄이기에서 선택이 바뀌는 투명도 전환 시간(초).
  public static var reducedFade: Double {
    0.2
  }

  /// 누를 수 있는 최소 높이(pt).
  static var minimumHeight: CGFloat {
    44
  }

  @Binding private var selection: Value
  private let tabs: [Tab]
  @Namespace private var namespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(selection: Binding<Value>, tabs: [Tab]) {
    self._selection = selection
    self.tabs = tabs
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(self.tabs.indices, id: \.self) { index in
        self.tabButton(self.tabs[index])
      }
    }
    .background(Capsule().fill(SnapColor.neutral))
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isTabBar)
  }

  private func tabButton(_ tab: Tab) -> some View {
    let isSelected = tab.value == self.selection
    return Button {
      withAnimation(self.reduceMotion ? .easeInOut(duration: Self.reducedFade) : Self.animation) {
        self.selection = tab.value
      }
    } label: {
      HStack(spacing: 4) {
        Text(tab.title)
        if let count = tab.count {
          Text("\(count)")
            .font(.snapNumber(.subheadline, weight: isSelected ? .bold : .regular))
            .snapRollingNumber(count)
        }
      }
      .font(.snap(.subheadline, weight: isSelected ? .bold : .regular))
      .foregroundStyle(isSelected ? SnapColor.ink : SnapColor.inkSecondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
      .background {
        self.selectionIndicator(isSelected)
          // 동작 줄이기면 선택 표시만 바로 옮긴다(선택 변경의 투명도 전환은 그대로).
          .transaction { transaction in
            if self.reduceMotion {
              transaction.animation = nil
            }
          }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.count.map { "\(tab.title), \($0)개" } ?? tab.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private func selectionIndicator(_ isSelected: Bool) -> some View {
    if isSelected {
      Capsule()
        .fill(SnapColor.card)
        .padding(3)
        .matchedGeometryEffect(id: "selection", in: self.namespace)
    }
  }
}
