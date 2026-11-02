import SwiftUI

public extension View {
  /// 화면에 처음 생기는 카드를 차례로 떠오르게 한다. `isRevealed` 가 거짓이면 숨겨 두고, 참으로 바뀌면 `index` 순서만큼 늦게
  /// 아래에서 위로 떠오르며 나타난다. 처음부터 참이면 움직이지 않고 바로 보인다.
  /// 동작 줄이기(Reduce Motion)면 위치는 그대로 두고 같은 지연으로 투명도만 바꾼다.
  func snapReveal(_ isRevealed: Bool, index: Int) -> some View {
    self.modifier(SnapRevealEffect(isRevealed: isRevealed, index: index))
  }
}

/// `snapReveal(_:index:)` 의 기준값.
public enum SnapReveal {
  /// 순서 하나당 늦추는 시간(초).
  public static let step = 0.04
  /// 이 순서 뒤로는 더 늦추지 않는다(긴 목록 끝이 오래 비어 있지 않게).
  public static let maxSteps = 12
  /// 떠오르기 전 아래로 내려 둔 거리(pt).
  public static let offset: CGFloat = 16
  /// 동작 줄이기에서 투명도가 바뀌는 시간(초).
  public static let reducedFade = 0.25

  /// `index` 번째 카드가 늦게 시작하는 시간(초). 0 보다 작은 순서는 0, 상한 뒤는 상한으로 본다.
  public static func delay(index: Int) -> Double {
    Double(min(max(index, 0), self.maxSteps)) * self.step
  }

  static func animation(index: Int, reduceMotion: Bool) -> Animation {
    let base: Animation = reduceMotion
      ? .easeInOut(duration: self.reducedFade)
      : .spring(response: 0.45, dampingFraction: 0.8)
    return base.delay(self.delay(index: index))
  }
}

private struct SnapRevealEffect: ViewModifier {
  let isRevealed: Bool
  let index: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .opacity(self.isRevealed ? 1 : 0)
      .offset(y: self.isRevealed || self.reduceMotion ? 0 : SnapReveal.offset)
      .animation(SnapReveal.animation(index: self.index, reduceMotion: self.reduceMotion), value: self.isRevealed)
  }
}
