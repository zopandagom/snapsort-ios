import ImageIO
import SwiftUI

/// 카드의 대표 사진 모자이크. 1~4장을 한 면에 나눠 담고 앞쪽(최신) 칸이 크다. 장식이라 VoiceOver 에서 읽지 않는다.
/// 칸 배치는 `layout(count:)` 의 단위 정사각형 표를 주어진 비율로 늘려 쓴다(넓은 카드도 같은 표).
public struct CoverMosaic: View {
  public enum Tile {
    /// 아직 읽지 않았거나 읽는 중. 중립 면이고 진행 표시는 없다.
    case pending
    /// 회전하지 않은 픽셀과 바르게 보이는 방향 (Core `AnalysisImage` 의 두 값).
    case image(CGImage, orientation: CGImagePropertyOrientation)
    /// 보일 수 없는 사진(iCloud 에만 있음·없음·실패)이나 대표가 없는 카드. 아이콘 칸 색 면 위에 아이콘.
    case glyph
  }

  /// 칸 사이 간격(pt).
  static let spacing: CGFloat = 3

  private let tiles: [Tile]
  private let glyph: SnapGlyph
  private let aspectRatio: CGFloat

  /// - Parameters:
  ///   - tiles: 앞쪽이 큰 칸. 비어 있으면 `.glyph` 한 칸, 5장 이상이면 앞 4장만 보인다.
  ///   - glyph: `.glyph` 칸에 그릴 아이콘과 면 색(`palette.tile`).
  ///   - aspectRatio: 너비 / 높이.
  public init(_ tiles: [Tile], fallback glyph: SnapGlyph, aspectRatio: CGFloat) {
    self.tiles = tiles.isEmpty ? [.glyph] : Array(tiles.prefix(4))
    self.glyph = glyph
    self.aspectRatio = aspectRatio
  }

  public var body: some View {
    Color.clear
      .aspectRatio(self.aspectRatio, contentMode: .fit)
      .overlay {
        GeometryReader { proxy in
          let frames = Self.layout(count: self.tiles.count)
          ForEach(frames.indices, id: \.self) { index in
            let frame = Self.frame(frames[index], in: proxy.size)
            self.tileView(self.tiles[index])
              .frame(width: frame.width, height: frame.height)
              .clipped()
              .position(x: frame.midX, y: frame.midY)
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func tileView(_ tile: Tile) -> some View {
    switch tile {
    case .pending:
      Rectangle().fill(SnapColor.neutral)
    case let .image(cgImage, orientation):
      Image(decorative: cgImage, orientation: orientation)
        .resizable()
        .scaledToFill()
    case .glyph:
      Rectangle()
        .fill(self.glyph.palette.tile)
        .overlay {
          GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.4
            SnapIcon(self.glyph)
              .frame(width: side, height: side)
              .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
          }
        }
    }
  }

  /// 단위 칸을 실제 크기로 늘리고, 안쪽 경계에만 간격의 반씩 뺀다(바깥 가장자리는 카드 모서리에 붙는다).
  private static func frame(_ unit: CGRect, in size: CGSize) -> CGRect {
    let half = Self.spacing / 2
    // 1/3 같은 분수의 합이 1 에 조금 못 미쳐도 바깥 가장자리로 본다.
    let edge: CGFloat = 0.001
    let minX = unit.minX * size.width + (unit.minX > edge ? half : 0)
    let maxX = unit.maxX * size.width - (unit.maxX < 1 - edge ? half : 0)
    let minY = unit.minY * size.height + (unit.minY > edge ? half : 0)
    let maxY = unit.maxY * size.height - (unit.maxY < 1 - edge ? half : 0)
    return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
  }

  /// 칸 배치(단위 정사각형 기준, 간격 없음). 앞쪽(최신)이 크다.
  /// 1 = 전체, 2 = 좌우 반, 3 = 왼쪽 2/3 세로 전체 + 오른쪽 1/3 위·아래, 4 = 2×2. 0 이하는 1, 5 이상은 4로 본다.
  public static func layout(count: Int) -> [CGRect] {
    switch min(max(count, 1), 4) {
    case 1:
      [CGRect(x: 0, y: 0, width: 1, height: 1)]
    case 2:
      [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
    case 3:
      [
        CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1),
        CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 0.5),
        CGRect(x: 2.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5),
      ]
    default:
      [
        CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
        CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
      ]
    }
  }
}
