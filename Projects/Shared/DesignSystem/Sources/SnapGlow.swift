import SwiftUI

public extension View {
  /// 새로 나타난 알약 버튼(`.snapPrimary`·`.snapSecondary`)에 눈길을 끈다. 나타날 때 로즈 빛이 `SnapGlow.period` 주기로 3번 번진 뒤
  /// 옅은 빛으로 남는다(그 뒤는 다시 그리지 않는다). 사라졌다 다시 나타나면 처음부터 다시 번진다.
  /// 동작 줄이기(Reduce Motion)면 움직이지 않고 로즈 테두리만 둔다. 장식이라 VoiceOver 가 읽는 것은 바뀌지 않는다.
  func snapGlow() -> some View {
    self.modifier(SnapGlow())
  }
}

/// `snapGlow()` 의 빛. 세기(0 = 빛 없음, 1 = 가장 밝음)를 키프레임으로 바꾸고, 세기에 비례해 번짐 반경과 불투명도를 정한다.
public struct SnapGlow: ViewModifier {
  /// 한 번 번졌다 잦아드는 시간(초).
  public static let period: TimeInterval = 1.6
  /// 번짐이 끝난 뒤 남는 세기.
  public static let restLevel = 0.4
  /// 세기 1 일 때의 번짐 반경(pt)과 불투명도.
  static let peakRadius: CGFloat = 12
  static let peakOpacity = 0.6
  /// 동작 줄이기에서 두는 테두리 두께(pt).
  static let outlineWidth: CGFloat = 2

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  public init() {}

  /// 나타날 때 세기의 흐름: 쉼 → 3번 번짐(올라 반 주기, 내려 반 주기) → 마지막은 쉼 세기로 내려 멈춘다. 시작과 끝 모두 쉼 세기라
  /// 키프레임이 돌기 전·끝난 뒤 값이 같다.
  @KeyframesBuilder<Double>
  public static var keyframes: some Keyframes<Double> {
    KeyframeTrack {
      CubicKeyframe(1, duration: Self.period / 2)
      CubicKeyframe(0, duration: Self.period / 2)
      CubicKeyframe(1, duration: Self.period / 2)
      CubicKeyframe(0, duration: Self.period / 2)
      CubicKeyframe(1, duration: Self.period / 2)
      CubicKeyframe(Self.restLevel, duration: Self.period / 2)
    }
  }

  public func body(content: Content) -> some View {
    if self.reduceMotion {
      content.overlay {
        Capsule().strokeBorder(SnapColor.rose, lineWidth: Self.outlineWidth)
      }
    } else {
      content
        .keyframeAnimator(initialValue: Self.restLevel, trigger: self.hasAppeared) { view, level in
          view.background {
            Capsule()
              .fill(SnapColor.rose.opacity(Self.peakOpacity * level))
              .blur(radius: Self.peakRadius * level)
          }
        } keyframes: { _ in
          Self.keyframes
        }
        .onAppear {
          self.hasAppeared = true
        }
    }
  }
}
