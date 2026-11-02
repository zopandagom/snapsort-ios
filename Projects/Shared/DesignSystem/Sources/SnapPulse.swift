import SwiftUI

public extension View {
  /// 곧 다가오는 것(예: 3일 안에 만료되는 기프티콘 배지)을 천천히 숨 쉬듯 키웠다 줄이기를 되풀이한다. `isActive` 가 거짓이면 움직이지 않는다.
  /// 동작 줄이기(Reduce Motion)면 1배로 멈춘다. 켜짐이나 동작 줄이기가 바뀌면 새로 시작해 커진 채 멈추지 않는다.
  func snapPulse(_ isActive: Bool) -> some View {
    self.modifier(SnapPulseEffect(isActive: isActive))
  }
}

/// `snapPulse(_:)` 의 기준값.
public enum SnapPulse {
  /// 가장 커질 때의 배율.
  public static let peakScale: CGFloat = 1.06
  /// 커졌다 돌아오는 한 호흡(초).
  public static let period: TimeInterval = 2.4

  /// 오갈 배율. 켜져 있고 동작 줄이기가 아니면 1 과 `peakScale`, 아니면 1 한 단계(움직이지 않는다).
  public static func phases(isActive: Bool, reduceMotion: Bool) -> [CGFloat] {
    isActive && !reduceMotion ? [1, self.peakScale] : [1]
  }
}

private struct SnapPulseEffect: ViewModifier {
  let isActive: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let phases = SnapPulse.phases(isActive: self.isActive, reduceMotion: self.reduceMotion)
    content
      .phaseAnimator(phases) { view, scale in
        view.scaleEffect(scale)
      } animation: { _ in
        .easeInOut(duration: SnapPulse.period / 2)
      }
      .id(phases.count)
  }
}
