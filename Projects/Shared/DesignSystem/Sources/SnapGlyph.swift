import SwiftUI

/// 직접 그린 카테고리 아이콘 (디자인 시안의 32×32 SVG 를 그대로 옮긴 좌표). 이름은 그린 모양이고,
/// 어느 카테고리에 쓰는지는 화면 쪽(Feature)이 정한다(DesignSystem 은 Core 를 모른다).
public enum SnapGlyph: CaseIterable, Sendable {
  case gift
  case receipt
  case chatBubble
  case shoppingBag
  case mapPin
  case document
  case suitcase
  case bowl
  case person
  case paw
  case mountain
  case grid
}

/// 아이콘 한 벌의 색. 칸 바탕(`tile`), 선(`line`), 흰 면(`surface`), 보조 면(`soft`)과 그 선(`softLine`).
public struct GlyphPalette: Hashable, Sendable {
  public let tile: ColorToken
  public let line: ColorToken
  public let surface: ColorToken
  public let soft: ColorToken
  public let softLine: ColorToken

  init(tile: ColorToken, line: ColorToken, surface: ColorToken, soft: ColorToken? = nil, softLine: ColorToken? = nil) {
    self.tile = tile
    self.line = line
    self.surface = surface
    self.soft = soft ?? surface
    self.softLine = softLine ?? line
  }
}

public extension SnapGlyph {
  /// 시안의 라이트 값. 다크 값은 같은 색상에서 선은 밝게, 칸은 어둡게 옮긴 값이다.
  var palette: GlyphPalette {
    switch self {
    case .gift:
      GlyphPalette(
        tile: ColorToken(light: 0xFFE1EA, dark: 0x4D232F),
        line: ColorToken(light: 0xD9466F, dark: 0xE78CA6),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x48343B),
        soft: ColorToken(light: 0xFFB3C6, dark: 0xBB8492)
      )
    case .receipt:
      GlyphPalette(
        tile: ColorToken(light: 0xFFE9D9, dark: 0x492A1D),
        line: ColorToken(light: 0xC8612A, dark: 0xDD9D7B),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x473734)
      )
    case .chatBubble:
      GlyphPalette(
        tile: ColorToken(light: 0xECE6FF, dark: 0x35294D),
        line: ColorToken(light: 0x7C5CE0, dark: 0xAE9AEC),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x3F3647)
      )
    case .shoppingBag:
      GlyphPalette(
        tile: ColorToken(light: 0xFBE3F3, dark: 0x422236),
        line: ColorToken(light: 0xB0408A, dark: 0xCE89B6),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x44333E),
        soft: ColorToken(light: 0xF5A3D6, dark: 0xB4799D)
      )
    case .mapPin:
      GlyphPalette(
        tile: ColorToken(light: 0xDDF5EE, dark: 0x213A35),
        line: ColorToken(light: 0x2E9E83, dark: 0x7DC3B2),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x373D3D),
        soft: ColorToken(light: 0x8EDDC6, dark: 0x6CA292)
      )
    case .document:
      GlyphPalette(
        tile: ColorToken(light: 0xE2ECFF, dark: 0x29324A),
        line: ColorToken(light: 0x4E7FD6, dark: 0x91B0E6),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x3A3A46)
      )
    case .suitcase:
      GlyphPalette(
        tile: ColorToken(light: 0xDDF1FB, dark: 0x213442),
        line: ColorToken(light: 0x2F86B8, dark: 0x7EB4D3),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x373A43),
        soft: ColorToken(light: 0x9AD3F0, dark: 0x749BB0)
      )
    case .bowl:
      GlyphPalette(
        tile: ColorToken(light: 0xFFF3CC, dark: 0x443415),
        line: ColorToken(light: 0xB5850B, dark: 0xD1B368),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x453A31)
      )
    case .person:
      GlyphPalette(
        tile: ColorToken(light: 0xFFE6DC, dark: 0x492A23),
        line: ColorToken(light: 0xC9603E, dark: 0xDE9C87),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x473636)
      )
    case .paw:
      GlyphPalette(
        tile: ColorToken(light: 0xF5E8DC, dark: 0x3B2B23),
        line: ColorToken(light: 0x95653F, dark: 0xBDA088),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x423737)
      )
    case .mountain:
      GlyphPalette(
        tile: ColorToken(light: 0xE5F2DD, dark: 0x293522),
        line: ColorToken(light: 0x4F8A3C, dark: 0x92B686),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x3B3B36),
        soft: ColorToken(light: 0xFFD66B, dark: 0xBB9D52),
        softLine: ColorToken(light: 0xE0A800, dark: 0xD1A93A)
      )
    case .grid:
      GlyphPalette(
        tile: ColorToken(light: 0xECEBF3, dark: 0x312D35),
        line: ColorToken(light: 0x6E6A86, dark: 0xA5A3B4),
        surface: ColorToken(light: 0xFFFFFF, dark: 0x3E373E),
        soft: ColorToken(light: 0xD6D3E6, dark: 0x9E9BA8)
      )
    }
  }
}

// MARK: - 모양

/// 한 겹: 32×32 좌표의 경로와 칠·선 역할. 선 굵기는 시안의 2.2(쇼핑 하트만 1.6).
struct GlyphLayer {
  enum Role {
    case surface
    case line
    case soft
    case softLine
  }

  var path: Path
  var fill: Role?
  var stroke: Role?
  var lineWidth: CGFloat = 2.2
}

extension SnapGlyph {
  static let canvasSize: CGFloat = 32

  var layers: [GlyphLayer] {
    switch self {
    case .gift: Self.giftLayers
    case .receipt: Self.receiptLayers
    case .chatBubble: Self.chatBubbleLayers
    case .shoppingBag: Self.shoppingBagLayers
    case .mapPin: Self.mapPinLayers
    case .document: Self.documentLayers
    case .suitcase: Self.suitcaseLayers
    case .bowl: Self.bowlLayers
    case .person: Self.personLayers
    case .paw: Self.pawLayers
    case .mountain: Self.mountainLayers
    case .grid: Self.gridLayers
    }
  }

  private static var giftLayers: [GlyphLayer] {
    [
      GlyphLayer(path: .roundedRect(6, 14, 20, 12, 3), fill: .soft, stroke: .line),
      GlyphLayer(path: .roundedRect(5, 10, 22, 5, 2), fill: .surface, stroke: .line),
      GlyphLayer(path: .lines([(16, 10), (16, 26)]), stroke: .line),
      GlyphLayer(path: Path { path in
        path.move(to: CGPoint(x: 16, y: 10))
        path.addCurve(to: CGPoint(x: 11.5, y: 10), control1: CGPoint(x: 13, y: 5), control2: CGPoint(x: 8, y: 7))
        path.move(to: CGPoint(x: 16, y: 10))
        path.addCurve(to: CGPoint(x: 20.5, y: 10), control1: CGPoint(x: 19, y: 5), control2: CGPoint(x: 24, y: 7))
      }, stroke: .line),
    ]
  }

  private static var receiptLayers: [GlyphLayer] {
    [
      GlyphLayer(
        path: .polygon([(9, 5), (23, 5), (23, 27), (19.5, 25), (16, 27), (12.5, 25), (9, 27)]),
        fill: .surface,
        stroke: .line
      ),
      GlyphLayer(path: .segments([[(13, 11), (19, 11)], [(13, 15), (19, 15)], [(13, 19), (16, 19)]]), stroke: .line),
    ]
  }

  private static var chatBubbleLayers: [GlyphLayer] {
    let bubble = Path { path in
      path.move(to: CGPoint(x: 10, y: 6))
      path.addLine(to: CGPoint(x: 22, y: 6))
      path.addArc(tangent1End: CGPoint(x: 26, y: 6), tangent2End: CGPoint(x: 26, y: 10), radius: 4)
      path.addLine(to: CGPoint(x: 26, y: 17))
      path.addArc(tangent1End: CGPoint(x: 26, y: 21), tangent2End: CGPoint(x: 22, y: 21), radius: 4)
      path.addLine(to: CGPoint(x: 14, y: 21))
      path.addLine(to: CGPoint(x: 9, y: 25))
      path.addLine(to: CGPoint(x: 9, y: 21))
      path.addQuadCurve(to: CGPoint(x: 6, y: 17), control: CGPoint(x: 6, y: 21))
      path.addLine(to: CGPoint(x: 6, y: 10))
      path.addArc(tangent1End: CGPoint(x: 6, y: 6), tangent2End: CGPoint(x: 10, y: 6), radius: 4)
      path.closeSubpath()
    }
    return [
      GlyphLayer(path: bubble, fill: .surface, stroke: .line),
      GlyphLayer(path: .circles([(12, 13.5), (16, 13.5), (20, 13.5)], radius: 1.2), fill: .line, stroke: .line),
    ]
  }

  private static var shoppingBagLayers: [GlyphLayer] {
    let heart = Path { path in
      path.move(to: CGPoint(x: 16, y: 22))
      path.addCurve(to: CGPoint(x: 14.2, y: 16.6), control1: CGPoint(x: 13, y: 20), control2: CGPoint(x: 12.5, y: 17.5))
      path.addCurve(to: CGPoint(x: 16, y: 17), control1: CGPoint(x: 15.2, y: 16.1), control2: CGPoint(x: 16, y: 17))
      path.addCurve(to: CGPoint(x: 17.8, y: 16.6), control1: CGPoint(x: 16, y: 17), control2: CGPoint(x: 16.8, y: 16.1))
      path.addCurve(to: CGPoint(x: 16, y: 22), control1: CGPoint(x: 19.5, y: 17.5), control2: CGPoint(x: 19, y: 20))
      path.closeSubpath()
    }
    let handle = Path { path in
      path.move(to: CGPoint(x: 12, y: 11))
      path.addLine(to: CGPoint(x: 12, y: 9))
      path.addArc(
        center: CGPoint(x: 16, y: 9),
        radius: 4,
        startAngle: .degrees(180),
        endAngle: .degrees(0),
        clockwise: false
      )
      path.addLine(to: CGPoint(x: 20, y: 11))
    }
    return [
      GlyphLayer(path: .roundedRect(7, 11, 18, 15, 3), fill: .surface, stroke: .line),
      GlyphLayer(path: handle, stroke: .line),
      GlyphLayer(path: heart, fill: .soft, stroke: .line, lineWidth: 1.6),
    ]
  }

  private static var mapPinLayers: [GlyphLayer] {
    let pin = Path { path in
      path.move(to: CGPoint(x: 16, y: 27))
      path.addCurve(to: CGPoint(x: 8, y: 14), control1: CGPoint(x: 16, y: 27), control2: CGPoint(x: 8, y: 19.5))
      path.addArc(
        center: CGPoint(x: 16, y: 14),
        radius: 8,
        startAngle: .degrees(180),
        endAngle: .degrees(0),
        clockwise: false
      )
      path.addCurve(to: CGPoint(x: 16, y: 27), control1: CGPoint(x: 24, y: 19.5), control2: CGPoint(x: 16, y: 27))
      path.closeSubpath()
    }
    return [
      GlyphLayer(path: pin, fill: .surface, stroke: .line),
      GlyphLayer(path: .circles([(16, 14)], radius: 3), fill: .soft, stroke: .line),
    ]
  }

  private static var documentLayers: [GlyphLayer] {
    [
      GlyphLayer(path: .roundedRect(8, 5, 16, 22, 3), fill: .surface, stroke: .line),
      GlyphLayer(path: .segments([[(12, 11), (20, 11)], [(12, 15), (20, 15)], [(12, 19), (17, 19)]]), stroke: .line),
    ]
  }

  private static var suitcaseLayers: [GlyphLayer] {
    [
      GlyphLayer(path: .roundedRect(6, 11, 20, 14, 3), fill: .surface, stroke: .line),
      GlyphLayer(path: .lines([(12, 11), (12, 8), (20, 8), (20, 11)]), stroke: .line),
      GlyphLayer(path: .lines([(6, 17), (26, 17)]), stroke: .soft),
    ]
  }

  private static var bowlLayers: [GlyphLayer] {
    // SVG 의 반타원 호(A11 9)를 3차 곡선 둘로 옮긴다.
    let kappa: CGFloat = 0.5523
    let bowl = Path { path in
      path.move(to: CGPoint(x: 5, y: 16))
      path.addLine(to: CGPoint(x: 27, y: 16))
      path.addCurve(
        to: CGPoint(x: 16, y: 25),
        control1: CGPoint(x: 27, y: 16 + 9 * kappa),
        control2: CGPoint(x: 16 + 11 * kappa, y: 25)
      )
      path.addCurve(
        to: CGPoint(x: 5, y: 16),
        control1: CGPoint(x: 16 - 11 * kappa, y: 25),
        control2: CGPoint(x: 5, y: 16 + 9 * kappa)
      )
      path.closeSubpath()
    }
    let steam = Path { path in
      for x: CGFloat in [12, 17, 22] {
        path.move(to: CGPoint(x: x, y: 12))
        path.addCurve(to: CGPoint(x: x, y: 6), control1: CGPoint(x: x - 1, y: 10), control2: CGPoint(x: x + 1, y: 9))
      }
    }
    return [
      GlyphLayer(path: bowl, fill: .surface, stroke: .line),
      GlyphLayer(path: steam, stroke: .line),
    ]
  }

  private static var personLayers: [GlyphLayer] {
    // SVG 의 반타원 호(A9 8)를 3차 곡선 둘로 옮긴다.
    let kappa: CGFloat = 0.5523
    let body = Path { path in
      path.move(to: CGPoint(x: 7, y: 26))
      path.addCurve(
        to: CGPoint(x: 16, y: 18),
        control1: CGPoint(x: 7, y: 26 - 8 * kappa),
        control2: CGPoint(x: 16 - 9 * kappa, y: 18)
      )
      path.addCurve(
        to: CGPoint(x: 25, y: 26),
        control1: CGPoint(x: 16 + 9 * kappa, y: 18),
        control2: CGPoint(x: 25, y: 26 - 8 * kappa)
      )
      path.closeSubpath()
    }
    return [
      GlyphLayer(path: .circles([(16, 11)], radius: 5), fill: .surface, stroke: .line),
      GlyphLayer(path: body, fill: .surface, stroke: .line),
    ]
  }

  private static var pawLayers: [GlyphLayer] {
    [
      GlyphLayer(path: Path(ellipseIn: CGRect(x: 10, y: 16, width: 12, height: 10)), fill: .surface, stroke: .line),
      GlyphLayer(path: .circles([(8.5, 14), (13, 9), (19, 9), (23.5, 14)], radius: 2.5), fill: .surface, stroke: .line),
    ]
  }

  private static var mountainLayers: [GlyphLayer] {
    [
      GlyphLayer(path: .polygon([(4, 25), (12, 14), (17, 20), (20, 16), (28, 25)]), fill: .surface, stroke: .line),
      GlyphLayer(path: .circles([(23, 9)], radius: 3), fill: .soft, stroke: .softLine),
    ]
  }

  private static var gridLayers: [GlyphLayer] {
    [
      GlyphLayer(path: .roundedRect(6, 6, 8.5, 8.5, 2.5), fill: .surface, stroke: .line),
      GlyphLayer(path: .roundedRect(17.5, 6, 8.5, 8.5, 2.5), fill: .surface, stroke: .line),
      GlyphLayer(path: .roundedRect(6, 17.5, 8.5, 8.5, 2.5), fill: .surface, stroke: .line),
      GlyphLayer(path: .roundedRect(17.5, 17.5, 8.5, 8.5, 2.5), fill: .soft, stroke: .line),
    ]
  }
}

private extension Path {
  static func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
  }

  /// 열린 꺾은선.
  static func lines(_ points: [(CGFloat, CGFloat)]) -> Path {
    Path { path in
      path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
    }
  }

  /// 따로 떨어진 꺾은선 여러 개.
  static func segments(_ segments: [[(CGFloat, CGFloat)]]) -> Path {
    Path { path in
      for points in segments {
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
      }
    }
  }

  static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
    Path { path in
      path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
      path.closeSubpath()
    }
  }

  static func circles(_ centers: [(CGFloat, CGFloat)], radius: CGFloat) -> Path {
    Path { path in
      for center in centers {
        path.addEllipse(in: CGRect(x: center.0 - radius, y: center.1 - radius, width: radius * 2, height: radius * 2))
      }
    }
  }
}
