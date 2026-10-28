import SwiftUI

/// 카테고리 아이콘 그림. 주어진 칸에 맞춰 늘어나고(정사각형), 선 굵기도 함께 늘어난다. 장식이라 VoiceOver 에서 읽지 않는다.
public struct SnapIcon: View {
  public enum Style: Sendable {
    /// 시안 색 (`SnapGlyph.palette`).
    case color
    /// 단색. 흰 면을 비우고 선은 현재 전경색, 보조 면은 `.secondary` 로 그린다. 잠금 화면 위젯처럼 색을 쓰지 않는 곳에 쓴다.
    case monochrome
  }

  private let glyph: SnapGlyph
  private let style: Style

  public init(_ glyph: SnapGlyph, style: Style = .color) {
    self.glyph = glyph
    self.style = style
  }

  public var body: some View {
    Canvas { [glyph, style] context, size in
      let scale = min(size.width, size.height) / SnapGlyph.canvasSize
      context.translateBy(
        x: (size.width - SnapGlyph.canvasSize * scale) / 2,
        y: (size.height - SnapGlyph.canvasSize * scale) / 2
      )
      context.scaleBy(x: scale, y: scale)
      let palette = glyph.palette
      for layer in glyph.layers {
        if let role = layer.fill, let shading = Self.shading(role, palette: palette, style: style, isFill: true) {
          context.fill(layer.path, with: shading)
        }
        if let role = layer.stroke, let shading = Self.shading(role, palette: palette, style: style, isFill: false) {
          context.stroke(
            layer.path,
            with: shading,
            style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round, lineJoin: .round)
          )
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private static func shading(
    _ role: GlyphLayer.Role,
    palette: GlyphPalette,
    style: Style,
    isFill: Bool
  ) -> GraphicsContext.Shading? {
    switch style {
    case .color:
      switch role {
      case .surface: .style(palette.surface)
      case .line: .style(palette.line)
      case .soft: .style(palette.soft)
      case .softLine: .style(palette.softLine)
      }
    case .monochrome:
      switch role {
      case .surface: nil
      case .line, .softLine: .style(.primary)
      case .soft:
        if isFill {
          .style(.secondary)
        } else {
          .style(.primary)
        }
      }
    }
  }
}

/// 둥근 색 칸 위의 카테고리 아이콘. 모서리는 칸의 0.3125 (시안: 칸 64 에 모서리 20).
public struct IconTile: View {
  /// 칸 대비 아이콘 비율. 큰 칸은 시안 아이콘 표(칸 64 에 36), 목록 줄 같은 작은 칸은 시안 메인 화면(칸 32 에 22).
  public enum Scale: CGFloat, Sendable {
    case large = 0.5625
    case compact = 0.6875
  }

  private let glyph: SnapGlyph
  private let size: CGFloat
  private let scale: Scale

  public init(_ glyph: SnapGlyph, size: CGFloat, scale: Scale = .large) {
    self.glyph = glyph
    self.size = size
    self.scale = scale
  }

  public var body: some View {
    RoundedRectangle(cornerRadius: self.size * 0.3125, style: .continuous)
      .fill(self.glyph.palette.tile)
      .frame(width: self.size, height: self.size)
      .overlay {
        SnapIcon(self.glyph)
          .frame(width: self.size * self.scale.rawValue, height: self.size * self.scale.rawValue)
      }
      .accessibilityHidden(true)
  }
}
