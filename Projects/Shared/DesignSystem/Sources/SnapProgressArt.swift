import SwiftUI

/// 분류 진행 그림(시안 Loading). 장식이라 VoiceOver 에서 읽지 않는다. 동작 줄이기면 한 장면에 멈춘다.
/// 고정 크기로 그리고 좁은 폭에서는 줄인다. 사진은 쓰지 않고 색 도형과 카테고리 아이콘만 그린다.
public struct SnapProgressArt: View {
  public enum Stage: Sendable {
    /// 1단계: 카드가 기프티콘·영수증·대화 칸으로 떨어지고 칸이 살짝 커진다.
    case sorting
    /// 2단계: 문서 위로 스캔선이 오르내리고 별이 반짝인다.
    case reading
  }

  private let stage: Stage

  public init(_ stage: Stage) {
    self.stage = stage
  }

  public var body: some View {
    Group {
      switch self.stage {
      case .sorting: SortingArt()
      case .reading: ReadingArt()
      }
    }
    .accessibilityHidden(true)
  }
}

// MARK: - 1단계

public extension SnapProgressArt {
  /// 1단계 한 주기(초). 칸 셋이 1/3 주기씩 늦게 돈다.
  static let sortingPeriod: TimeInterval = 2.4
  /// 떨어지는 카드: 위에서 나타나 55% 에 칸 위에 닿고 70% 에 칸 안으로 사라진다.
  static let cardOpacity = LoopTrack([0: 0, 0.15: 1, 0.55: 1, 0.7: 0, 1: 0])
  static let cardY = LoopTrack([0: -70, 0.55: 18, 0.7: 40, 1: 40])
  /// 0 에서 칸 방향까지의 비율. 55% 에 칸 위에 온다.
  static let cardTravel = LoopTrack([0: 0, 0.55: 1, 1: 1])
  /// 카드가 닿은 직후(68%) 칸이 커졌다가 돌아온다.
  static let tilePop = LoopTrack([0: 1, 0.6: 1, 0.68: 1.12, 1: 1])
}

private struct SortingArt: View {
  private struct Lane {
    let glyph: SnapGlyph
    let tileX: CGFloat
    let rotation: LoopTrack
  }

  private static let size = CGSize(width: 300, height: 190)
  private static let cardStart = CGPoint(x: 150, y: 84)
  private static let lanes = [
    Lane(glyph: .gift, tileX: 54, rotation: LoopTrack([0: -12, 0.55: -4, 0.7: 0, 1: 0])),
    Lane(glyph: .receipt, tileX: 150, rotation: LoopTrack([0: 10, 0.55: 2, 0.7: 0, 1: 0])),
    Lane(glyph: .chatBubble, tileX: 246, rotation: LoopTrack([0: -6, 0.55: 6, 0.7: 0, 1: 0])),
  ]

  var body: some View {
    FittedArt(size: Self.size) {
      // 동작 줄이기면 첫 칸 카드가 막 닿은 장면에서 멈춘다.
      LoopingTimeline(stillTime: SnapProgressArt.sortingPeriod * 0.5) { time in
        ZStack {
          ForEach(Self.lanes.indices, id: \.self) { index in
            self.tile(Self.lanes[index], cycle: self.cycle(time, lane: index))
          }
          ForEach(Self.lanes.indices, id: \.self) { index in
            self.card(Self.lanes[index], cycle: self.cycle(time, lane: index))
          }
        }
      }
    }
  }

  private func cycle(_ time: TimeInterval, lane: Int) -> Double {
    time / SnapProgressArt.sortingPeriod - Double(lane) / Double(Self.lanes.count)
  }

  private func tile(_ lane: Lane, cycle: Double) -> some View {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
      .fill(lane.glyph.palette.tile)
      .frame(width: 84, height: 64)
      .overlay {
        SnapIcon(lane.glyph)
          .frame(width: 34, height: 34)
      }
      .scaleEffect(SnapProgressArt.tilePop.value(at: cycle))
      .position(x: lane.tileX, y: Self.size.height - 32)
  }

  private func card(_ lane: Lane, cycle: Double) -> some View {
    let travel = SnapProgressArt.cardTravel.value(at: cycle)
    return RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(lane.glyph.palette.line.opacity(0.45))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(SnapColor.card, lineWidth: 2.5)
      }
      .frame(width: 38, height: 48)
      .rotationEffect(.degrees(lane.rotation.value(at: cycle)))
      .opacity(SnapProgressArt.cardOpacity.value(at: cycle))
      .position(
        x: Self.cardStart.x + (lane.tileX - Self.cardStart.x) * travel,
        y: Self.cardStart.y + SnapProgressArt.cardY.value(at: cycle)
      )
  }
}

// MARK: - 2단계

public extension SnapProgressArt {
  /// 스캔선이 문서 위에서 아래로 내려갔다가 돌아온다.
  static let scanPeriod: TimeInterval = 1.8
  static let scanOffset = LoopTrack([0: 0, 0.5: 52, 1: 0])
  /// 별이 작아졌다 커지며 반짝인다.
  static let twinklePeriod: TimeInterval = 1.4
  static let twinkleScale = LoopTrack([0: 0.6, 0.5: 1, 1: 0.6])
  static let twinkleOpacity = LoopTrack([0: 0.4, 0.5: 1, 1: 0.4])
}

private struct ReadingArt: View {
  private static let size = CGSize(width: 120, height: 120)
  /// 문서 안 글줄 폭(문서 안쪽 폭 대비).
  private static let lineWidths: [CGFloat] = [1, 0.75, 1, 0.55]

  var body: some View {
    FittedArt(size: Self.size) {
      // 동작 줄이기면 스캔선이 문서 가운데쯤 온 장면에서 멈춘다.
      LoopingTimeline(stillTime: SnapProgressArt.scanPeriod * 0.25) { time in
        ZStack(alignment: .topLeading) {
          self.document
            .offset(x: 22, y: 10)
          Capsule()
            .fill(SnapColor.lilac.opacity(0.55))
            .frame(width: 88, height: 6)
            .offset(x: 16, y: 22 + SnapProgressArt.scanOffset.value(at: time / SnapProgressArt.scanPeriod))
          self.star(cycle: time / SnapProgressArt.twinklePeriod)
            .offset(x: Self.size.width - 26)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
      }
    }
  }

  private var document: some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(Self.lineWidths.indices, id: \.self) { index in
        Capsule()
          .fill(SnapColor.lilacSoft)
          .frame(width: 52 * Self.lineWidths[index], height: 6)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 18)
    .frame(width: 76, height: 100, alignment: .topLeading)
    .background(SnapColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(SnapColor.lilac, lineWidth: 2.5)
    }
  }

  /// 시안의 네 갈래 별(32 칸 기준)을 26pt 로 그린다.
  private func star(cycle: Double) -> some View {
    Canvas { context, size in
      let scale = size.width / 32
      context.scaleBy(x: scale, y: scale)
      var path = Path()
      path.move(to: CGPoint(x: 16, y: 3))
      path.addLine(to: CGPoint(x: 19, y: 11))
      path.addLine(to: CGPoint(x: 27, y: 14))
      path.addLine(to: CGPoint(x: 19, y: 17))
      path.addLine(to: CGPoint(x: 16, y: 25))
      path.addLine(to: CGPoint(x: 13, y: 17))
      path.addLine(to: CGPoint(x: 5, y: 14))
      path.addLine(to: CGPoint(x: 13, y: 11))
      path.closeSubpath()
      context.fill(path, with: .style(SnapColor.butter))
    }
    .frame(width: 26, height: 26)
    .scaleEffect(SnapProgressArt.twinkleScale.value(at: cycle))
    .opacity(SnapProgressArt.twinkleOpacity.value(at: cycle))
  }
}
