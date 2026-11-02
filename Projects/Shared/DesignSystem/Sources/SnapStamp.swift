import SwiftUI

/// 상태가 바뀐 것을 알리는 도장(예: 기프티콘을 사용함으로 옮길 때 썸네일 위 "사용"). 나타날 때 크게 기울어 내려와 찍히고
/// 쉬는 각도(`restAngle`)로 남는다. 동작 줄이기(Reduce Motion)면 크기·각도를 바꾸지 않고 쉬는 각도에서 투명도만 바꾼다.
/// 장식이라 VoiceOver 가 읽지 않는다(바뀐 사실은 쓰는 화면이 알린다).
/// 쓰는 화면이 도장 뒤의 색 빠짐·줄 빠짐에 이 기준값(`settle`·`exitDuration`·`exitOffset`·`fadedSaturation`)을 쓴다.
public struct SnapStamp: View {
  /// 찍힌 뒤 쉬는 각도.
  public static let restAngle = Angle.degrees(-12)
  /// 찍히기 전 각도와 크기 배율.
  static let startAngle = Angle.degrees(-24)
  static let startScale: CGFloat = 1.8
  /// 찍힐 때 살짝 눌리는 크기 배율.
  static let squashScale: CGFloat = 0.92
  /// 찍히는 데 걸리는 시간(초).
  public static let duration = 0.45
  /// 도장과 색 빠짐을 보여 둔 뒤 줄을 빼기까지 머무는 시간.
  public static let settle: Duration = .milliseconds(700)
  /// 줄이 빠지는 시간. `exitAnimation` 과 같다.
  public static let exitDuration: Duration = .milliseconds(250)
  /// 줄이 빠지며 옆으로 움직이는 거리(pt). 동작 줄이기면 움직이지 않는다.
  public static let exitOffset: CGFloat = 40
  /// 도장이 찍힌 썸네일의 채도.
  public static let fadedSaturation = 0.2
  /// 줄이 빠지는 애니메이션.
  public static let exitAnimation: Animation = .easeIn(duration: 0.25)
  /// 썸네일 색이 빠지는 애니메이션.
  public static let fadeAnimation: Animation = .easeOut(duration: Self.duration)

  /// 도장의 한 순간.
  public struct Pose: Equatable, Sendable {
    public var scale: CGFloat
    /// 각도(도).
    public var degrees: Double
    public var opacity: Double

    public init(scale: CGFloat, degrees: Double, opacity: Double) {
      self.scale = scale
      self.degrees = degrees
      self.opacity = opacity
    }
  }

  /// 찍힌 뒤 남는 모습.
  public static let restingPose = Pose(scale: 1, degrees: Self.restAngle.degrees, opacity: 1)

  /// 나타나기 직전 모습. 동작 줄이기면 크기·각도는 쉬는 값이고 투명하기만 하다.
  public static func initialPose(reduceMotion: Bool) -> Pose {
    reduceMotion
      ? Pose(scale: 1, degrees: self.restAngle.degrees, opacity: 0)
      : Pose(scale: self.startScale, degrees: self.startAngle.degrees, opacity: 0)
  }

  /// 크게·투명하게 시작해(처음 값으로 바로 옮긴다) 살짝 눌렸다가 쉬는 모습으로 끝난다.
  /// 시작 값은 `MoveKeyframe` 이 정하므로 키프레임은 `restingPose` 를 처음 값으로 둔다(끝난 뒤 값과 같아 튀지 않는다).
  @KeyframesBuilder<Pose>
  public static var keyframes: some Keyframes<Pose> {
    let start = Self.initialPose(reduceMotion: false)
    KeyframeTrack(\.scale) {
      MoveKeyframe(start.scale)
      CubicKeyframe(Self.squashScale, duration: Self.duration * 0.6)
      CubicKeyframe(1, duration: Self.duration * 0.4)
    }
    KeyframeTrack(\.degrees) {
      MoveKeyframe(start.degrees)
      CubicKeyframe(Self.restAngle.degrees, duration: Self.duration)
    }
    KeyframeTrack(\.opacity) {
      MoveKeyframe(0)
      LinearKeyframe(1, duration: Self.duration * 0.3)
      LinearKeyframe(1, duration: Self.duration * 0.7)
    }
  }

  private let text: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  public init(text: String) {
    self.text = text
  }

  public var body: some View {
    Group {
      if self.reduceMotion {
        self.label(Self.restingPose)
          .opacity(self.hasAppeared ? 1 : 0)
          .animation(.easeOut(duration: Self.duration), value: self.hasAppeared)
      } else {
        self.label(Self.restingPose)
          .keyframeAnimator(initialValue: Self.restingPose, trigger: self.hasAppeared) { _, pose in
            self.label(pose)
          } keyframes: { _ in
            Self.keyframes
          }
          // 키프레임이 돌기 전 한 프레임 동안 쉬는 모습이 보이지 않게 한다.
          .opacity(self.hasAppeared ? 1 : 0)
      }
    }
    .onAppear {
      self.hasAppeared = true
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private nonisolated func label(_ pose: Pose) -> some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    return Text(self.text)
      .font(.caption.weight(.heavy))
      .foregroundStyle(SnapColor.accent)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(shape.fill(SnapColor.card))
      .overlay(shape.strokeBorder(SnapColor.accent, lineWidth: 2))
      .scaleEffect(pose.scale)
      .rotationEffect(.degrees(pose.degrees))
      .opacity(pose.opacity)
  }
}
