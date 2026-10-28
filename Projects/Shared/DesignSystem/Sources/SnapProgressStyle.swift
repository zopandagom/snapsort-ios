import SwiftUI

/// 줄무늬가 흐르는 둥근 진행 막대(시안 Home "진행 카드"). 제목·현재 값 줄 아래에 막대를 둔다.
/// VoiceOver 에서는 시스템 막대(`.linear`)와 똑같이 읽힌다. 동작 줄이기면 줄무늬가 멈추고 값도 애니메이션 없이 바뀐다.
public struct SnapProgressStyle: ProgressViewStyle {
  /// 채움 / 트랙 색. 채움과 트랙은 라이트·다크 모두 그래픽 대비 3:1 이상이다(`SnapColorTests`).
  public enum Tint: CaseIterable, Sendable {
    /// 사진 분류(1단계).
    case rose
    /// 글자 읽기(2단계). 면용 라일락은 라이트 트랙과 대비가 모자라 채움은 `lilacText` 다.
    case lilac

    public var fill: ColorToken {
      switch self {
      case .rose: SnapColor.rose
      case .lilac: SnapColor.lilacText
      }
    }

    public var track: ColorToken {
      switch self {
      case .rose: SnapColor.blush
      case .lilac: SnapColor.lilacSoft
      }
    }
  }

  private let tint: Tint

  public init(tint: Tint) {
    self.tint = tint
  }

  public func makeBody(configuration: Configuration) -> some View {
    SnapProgressBody(configuration: configuration, tint: self.tint)
      .accessibilityRepresentation {
        ProgressView(configuration)
          .progressViewStyle(.linear)
      }
  }
}

public extension ProgressViewStyle where Self == SnapProgressStyle {
  static func snap(_ tint: SnapProgressStyle.Tint = .rose) -> SnapProgressStyle {
    SnapProgressStyle(tint: tint)
  }
}

private struct SnapProgressBody: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let configuration: ProgressViewStyleConfiguration
  let tint: SnapProgressStyle.Tint

  var body: some View {
    // 큰 글씨(접근성 크기)에서는 제목과 값을 위아래로 둬 둘 다 잘리지 않게 한다.
    let layout = self.dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    VStack(alignment: .leading, spacing: 8) {
      layout {
        self.configuration.label
          .font(.headline)
        if !self.dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: 0)
        }
        self.configuration.currentValueLabel
          .font(.subheadline.bold())
          .foregroundStyle(SnapColor.inkSecondary)
      }
      StripedBar(fraction: self.configuration.fractionCompleted ?? 0, tint: self.tint)
    }
  }
}

/// 트랙 위에 채움 막대를 두고 그 위로 흰 줄무늬를 흘린다.
private struct StripedBar: View {
  private static let height: CGFloat = 12
  /// 줄무늬 한 칸(가로)과 흐르는 속도(초당 pt).
  private static let stripePeriod: CGFloat = 16
  private static let stripeSpeed: CGFloat = 20

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let fraction: Double
  let tint: SnapProgressStyle.Tint

  var body: some View {
    GeometryReader { proxy in
      let clamped = min(max(self.fraction, 0), 1)
      // 조금이라도 진행했으면 둥근 끝이 보이게 막대 높이만큼은 채운다.
      let width = clamped > 0 ? max(proxy.size.width * clamped, Self.height) : 0
      Capsule()
        .fill(self.tint.track)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(self.tint.fill)
            .overlay {
              LoopingTimeline(stillTime: 0) { time in
                self.stripes(offset: CGFloat(time) * Self.stripeSpeed)
              }
            }
            .clipShape(Capsule())
            .frame(width: width)
            .animation(self.reduceMotion ? nil : .easeOut(duration: 0.35), value: width)
        }
    }
    .frame(height: Self.height)
  }

  /// 45° 기운 띠를 칸마다 그린다. `offset` 만큼 오른쪽으로 흐른다.
  private func stripes(offset: CGFloat) -> some View {
    Canvas { context, size in
      let period = Self.stripePeriod
      let shift = offset.truncatingRemainder(dividingBy: period)
      var x = -size.height - period + shift
      while x < size.width {
        var band = Path()
        band.move(to: CGPoint(x: x, y: size.height))
        band.addLine(to: CGPoint(x: x + size.height, y: 0))
        band.addLine(to: CGPoint(x: x + size.height + period / 2, y: 0))
        band.addLine(to: CGPoint(x: x + period / 2, y: size.height))
        band.closeSubpath()
        context.fill(band, with: .style(SnapColor.sheen.opacity(0.25)))
        x += period
      }
    }
  }
}
