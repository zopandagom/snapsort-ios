import SwiftUI

/// 축하 장식. 나타날 때 한 번, 작은 점들이 가운데에서 바깥으로 퍼지며 사라진다(끝나면 투명하다). 다시 나타나면 다시 터진다.
/// 다른 면 뒤(`background`, 아이콘을 가리지 않게)나 위(`overlay`)에 얹는다. 장식이라 VoiceOver 가 읽지 않고 누름도 받지 않는다. 동작 줄이기(Reduce Motion)면 그리지
/// 않는다.
public struct SnapSparkleBurst: View {
  /// 점 개수.
  public static let particleCount = 8
  /// 한 번 터지는 시간(초).
  public static let duration = 0.9
  /// 점이 가장 멀리 가는 거리(pt).
  public static let distance: CGFloat = 28
  /// 점 지름(pt).
  static let particleSize: CGFloat = 6

  /// 터짐의 한 순간. `spread` 는 0(가운데) ~ 1(`distance`), `opacity`·`scale` 은 점의 불투명도·크기.
  public struct Burst: Equatable, Sendable {
    public var spread: CGFloat
    public var opacity: Double
    public var scale: CGFloat

    /// 터지기 전과 끝난 뒤의 값. 투명해서 키프레임이 돌기 전·끝난 뒤 어느 쪽이든 보이지 않는다.
    public static let finished = Burst(spread: 1, opacity: 0, scale: 0.6)
  }

  /// 가운데에서 바로 밝게 나타나 바깥으로 퍼지고, 뒤 절반에 걸쳐 작아지며 사라진다.
  @KeyframesBuilder<Burst>
  public static var keyframes: some Keyframes<Burst> {
    KeyframeTrack(\.spread) {
      MoveKeyframe(0)
      CubicKeyframe(1, duration: Self.duration)
    }
    KeyframeTrack(\.opacity) {
      MoveKeyframe(0)
      LinearKeyframe(1, duration: Self.duration * 0.15)
      LinearKeyframe(1, duration: Self.duration * 0.35)
      CubicKeyframe(0, duration: Self.duration * 0.5)
    }
    KeyframeTrack(\.scale) {
      MoveKeyframe(0.4)
      CubicKeyframe(1, duration: Self.duration * 0.3)
      CubicKeyframe(0.6, duration: Self.duration * 0.7)
    }
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  public init() {}

  public var body: some View {
    if self.reduceMotion {
      EmptyView()
    } else {
      self.particles(Burst.finished)
        .keyframeAnimator(initialValue: Burst.finished, trigger: self.hasAppeared) { _, burst in
          self.particles(burst)
        } keyframes: { _ in
          Self.keyframes
        }
        .onAppear {
          self.hasAppeared = true
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
  }

  private nonisolated func particles(_ burst: Burst) -> some View {
    let colors = [SnapColor.rose, SnapColor.butter, SnapColor.lilac]
    return ZStack {
      ForEach(0 ..< Self.particleCount, id: \.self) { index in
        let angle = Double(index) / Double(Self.particleCount) * 2 * .pi
        Circle()
          .fill(colors[index % colors.count])
          .frame(width: Self.particleSize, height: Self.particleSize)
          .scaleEffect(burst.scale)
          .offset(
            x: cos(angle) * Self.distance * burst.spread,
            y: sin(angle) * Self.distance * burst.spread
          )
      }
    }
    .opacity(burst.opacity)
  }
}
