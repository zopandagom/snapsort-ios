import SwiftUI

/// 누를 수 있는 면(알약 버튼, 카드 링크)의 눌림 반응. 눌린 동안 살짝 작아졌다가 손을 떼면 스프링으로 튀어 돌아온다.
/// 동작 줄이기(Reduce Motion)면 크기를 바꾸지 않고 흐려지기만 한다.
public enum SnapPress {
  /// 눌린 동안의 크기 배율.
  public static let pressedScale: CGFloat = 0.96
  /// 동작 줄이기에서 눌린 동안의 불투명도.
  public static let reducedPressedOpacity = 0.75

  /// 눌림 상태와 동작 줄이기에 따른 크기 배율과 불투명도.
  public static func effect(isPressed: Bool, reduceMotion: Bool) -> (scale: CGFloat, opacity: Double) {
    guard isPressed else { return (1, 1) }
    return reduceMotion ? (1, self.reducedPressedOpacity) : (self.pressedScale, 1)
  }

  /// 누를 때는 빠르게 줄고, 뗄 때는 살짝 넘쳤다 돌아온다.
  static func animation(isPressed: Bool) -> Animation {
    isPressed ? .easeOut(duration: 0.12) : .spring(response: 0.4, dampingFraction: 0.55)
  }
}

extension View {
  /// `SnapPress` 반응을 얹는다. `ButtonStyle` 의 `configuration.isPressed` 를 넘긴다.
  func snapPressEffect(isPressed: Bool) -> some View {
    self.modifier(SnapPressEffect(isPressed: isPressed))
  }
}

private struct SnapPressEffect: ViewModifier {
  let isPressed: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let effect = SnapPress.effect(isPressed: self.isPressed, reduceMotion: self.reduceMotion)
    content
      .scaleEffect(effect.scale)
      .opacity(effect.opacity)
      .animation(self.reduceMotion ? nil : SnapPress.animation(isPressed: self.isPressed), value: self.isPressed)
  }
}

/// 카드 링크(`snapCard()` 를 입힌 `NavigationLink`·`Button`)의 버튼 스타일. 모양은 그대로 두고 `SnapPress` 눌림 반응만 더한다.
/// 누르는 영역은 카드 모양(모서리 20)이다.
public struct SnapCardButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .snapPressEffect(isPressed: configuration.isPressed)
  }
}

public extension ButtonStyle where Self == SnapCardButtonStyle {
  static var snapCard: SnapCardButtonStyle { SnapCardButtonStyle() }
}
