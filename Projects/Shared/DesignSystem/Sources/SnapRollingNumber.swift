import SwiftUI

public extension View {
  /// 숫자가 든 글자에 붙인다. `value` 가 바뀌면 바뀐 자리만 굴러가고(늘면 위로, 줄면 아래로), 동작 줄이기(Reduce Motion)면 바로 바뀐다.
  func snapRollingNumber(_ value: Int) -> some View {
    self.modifier(SnapRollingNumber(value: value))
  }
}

private struct SnapRollingNumber: ViewModifier {
  let value: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .contentTransition(.numericText(value: Double(self.value)))
      .animation(self.reduceMotion ? nil : .snappy, value: self.value)
  }
}
