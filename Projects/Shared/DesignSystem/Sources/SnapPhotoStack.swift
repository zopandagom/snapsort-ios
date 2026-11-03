import SwiftUI

/// 사진 더미 그림의 반짝이 한 개의 배율·불투명도.
public struct SnapPhotoSparkle: Equatable, Sendable {
  public var scale: CGFloat
  public var opacity: Double
}

/// 사진 더미 그림. 뒤에 기운 사진 장(라일락, 빈 화면은 블러시도)과 로즈 테두리 앞장(버터 해·로즈 산), 반짝이를 그린다.
/// 앱 아이콘과 같은 모티프라 빈 화면 그림(`.empty`)과 온보딩 앱 마크(`.appMark`)에 함께 쓴다. 주어진 칸에 맞춰 늘어난다(정사각형).
/// 장들은 `floatPeriod` 주기로 서로 엇갈려 천천히 떠 있고, 반짝이는 `twinklePeriod` 주기로 깜빡인다. 동작 줄이기(Reduce Motion)면
/// 둘 다 멈춘 쉼 모양(`Pose.rest`)으로 그린다. 장식이라 VoiceOver 에서 읽지 않고 누름도 받지 않는다.
public struct SnapPhotoStack: View {
  public enum Variant: Sendable {
    /// 빈 화면: 라일락·블러시 뒷장 + 앞장 + 버터 반짝이 2개.
    case empty
    /// 앱 마크: 앱 아이콘처럼 라일락 뒷장 + 앞장 + 로즈 반짝이 1개.
    case appMark
  }

  /// 그림 좌표계의 한 변(그림은 100×100 좌표로 그린 뒤 칸에 맞춰 늘린다).
  static let canvasSize: CGFloat = 100
  /// 떠 있기 한 주기(초).
  public static let floatPeriod: TimeInterval = 4
  /// 기준 크기(`referenceSize`)에서 위아래로 오가는 전체 거리(pt). 그림이 커지면 같은 비율로 커진다.
  public static let floatDistance: CGFloat = 5
  /// `floatDistance` 의 기준 그림 크기(pt).
  public static let referenceSize: CGFloat = 120
  /// 반짝이 한 번 깜빡이는 주기(초).
  public static let twinklePeriod: TimeInterval = 2.2
  /// 반짝이가 가장 작을 때·클 때의 배율과 불투명도.
  public static let twinkleScale: ClosedRange<CGFloat> = 0.7 ... 1.15
  public static let twinkleOpacity: ClosedRange<Double> = 0.5 ... 1

  /// 한 순간의 모양. `cardOffsets` 는 뒷장 라일락·뒷장 블러시·앞장의 세로 이동(그림 좌표, 아래가 +),
  /// `sparkles` 는 반짝이 두 개의 배율·불투명도다(앱 마크는 첫 번째만 쓴다).
  public struct Pose: Equatable, Sendable {
    public var cardOffsets: [CGFloat]
    public var sparkles: [SnapPhotoSparkle]

    /// 멈춘 모양. 동작 줄이기에서 쓴다.
    public static let rest = Pose(
      cardOffsets: [0, 0, 0],
      sparkles: [SnapPhotoSparkle(scale: 1, opacity: 1), SnapPhotoSparkle(scale: 1, opacity: 1)]
    )
  }

  /// `time`(초) 의 모양. `nil` 이면 멈춘 모양이다. 세 장은 주기의 1/3 씩, 두 반짝이는 반 주기씩 엇갈린다.
  public nonisolated static func pose(at time: TimeInterval?) -> Pose {
    guard let time else { return .rest }
    let halfDistance = self.floatDistance / self.referenceSize * self.canvasSize / 2
    let offsets = (0 ..< 3).map { index in
      let angle = 2 * Double.pi * (time / self.floatPeriod + Double(index) / 3)
      return -CGFloat(sin(angle)) * halfDistance
    }
    let sparkles = (0 ..< 2).map { index in
      let angle = 2 * Double.pi * (time / self.twinklePeriod + Double(index) / 2)
      let level = (1 - cos(angle)) / 2
      return SnapPhotoSparkle(
        scale: self.twinkleScale.lowerBound + (self.twinkleScale.upperBound - self.twinkleScale.lowerBound) * level,
        opacity: self.twinkleOpacity
          .lowerBound + (self.twinkleOpacity.upperBound - self.twinkleOpacity.lowerBound) * level
      )
    }
    return Pose(cardOffsets: offsets, sparkles: sparkles)
  }

  private let variant: Variant
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(_ variant: Variant = .empty) {
    self.variant = variant
  }

  public var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: self.reduceMotion)) { timeline in
      let pose = self.reduceMotion ? Pose.rest : Self.pose(at: timeline.date.timeIntervalSinceReferenceDate)
      Canvas { [variant] context, size in
        let scale = min(size.width, size.height) / Self.canvasSize
        context.translateBy(
          x: (size.width - Self.canvasSize * scale) / 2,
          y: (size.height - Self.canvasSize * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)
        Self.draw(variant, pose: pose, in: &context)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  // MARK: - 모양 (100×100 좌표)

  private static func draw(_ variant: Variant, pose: Pose, in context: inout GraphicsContext) {
    let lilacBack = self.tiltedCard(center: CGPoint(x: 40, y: 54), degrees: -10)
    context.fill(lilacBack.offsetBy(dx: 0, dy: pose.cardOffsets[0]), with: .style(SnapColor.lilac.opacity(0.55)))

    if variant == .empty {
      let blushBack = self.tiltedCard(center: CGPoint(x: 62, y: 52), degrees: 9)
        .offsetBy(dx: 0, dy: pose.cardOffsets[1])
      context.fill(blushBack, with: .style(SnapColor.blush))
      context.stroke(blushBack, with: .style(SnapColor.rose.opacity(0.35)), lineWidth: 1.5)
    }

    var front = context
    front.translateBy(x: 0, y: pose.cardOffsets[2])
    let card = Path(roundedRect: CGRect(x: 28, y: 20, width: 46, height: 60), cornerRadius: 10)
    front.fill(card, with: .style(SnapColor.card))
    front.stroke(card, with: .style(SnapColor.rose), lineWidth: 4.5)
    front.fill(Path(ellipseIn: CGRect(x: 57, y: 29, width: 12, height: 12)), with: .style(SnapColor.butter))
    let mountains = Path { path in
      path.addLines([
        CGPoint(x: 34, y: 70), CGPoint(x: 46, y: 53), CGPoint(x: 54, y: 62),
        CGPoint(x: 59, y: 57), CGPoint(x: 68, y: 70),
      ])
      path.closeSubpath()
    }
    front.fill(mountains, with: .style(SnapColor.rose.opacity(0.55)))

    switch variant {
    case .empty:
      self.drawSparkle(
        at: CGPoint(x: 86, y: 14),
        radius: 9,
        pose: pose.sparkles[0],
        color: SnapColor.butter,
        in: &context
      )
      self.drawSparkle(
        at: CGPoint(x: 14, y: 16),
        radius: 6,
        pose: pose.sparkles[1],
        color: SnapColor.butter,
        in: &context
      )
    case .appMark:
      // 앱 아이콘처럼 앞장 오른쪽 위 모서리에 걸친다(앞장과 함께 뜬다).
      self.drawSparkle(at: CGPoint(x: 76, y: 22), radius: 12, pose: pose.sparkles[0], color: SnapColor.rose, in: &front)
    }
  }

  /// 46×58 둥근 사진 장을 `center` 기준으로 `degrees` 만큼 기울인다.
  private static func tiltedCard(center: CGPoint, degrees: Double) -> Path {
    Path(roundedRect: CGRect(x: -23, y: -29, width: 46, height: 58), cornerRadius: 9)
      .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180))
      .offsetBy(dx: center.x, dy: center.y)
  }

  /// 네 갈래 반짝이. 가운데를 기준으로 커졌다 작아진다.
  private static func drawSparkle(
    at center: CGPoint,
    radius: CGFloat,
    pose: SnapPhotoSparkle,
    color: ColorToken,
    in context: inout GraphicsContext
  ) {
    let outer = radius * pose.scale
    let inner = outer * 0.38
    let star = Path { path in
      for step in 0 ..< 8 {
        let angle = Double(step) * .pi / 4 - .pi / 2
        let length = step.isMultiple(of: 2) ? outer : inner
        let point = CGPoint(x: center.x + CGFloat(cos(angle)) * length, y: center.y + CGFloat(sin(angle)) * length)
        if step == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
      path.closeSubpath()
    }
    var layer = context
    layer.opacity = pose.opacity
    layer.fill(star, with: .style(color))
  }
}
