import DesignSystem
import Foundation
import Testing

struct SnapColorTests {
  /// 글자 / 바탕 조합. 화면에서 글자로 쓰는 조합을 모두 적는다.
  struct TextPair {
    let name: String
    let text: ColorToken
    let background: ColorToken

    init(_ name: String, _ text: ColorToken, _ background: ColorToken) {
      self.name = name
      self.text = text
      self.background = background
    }
  }

  static let textPairs: [TextPair] = [
    TextPair("본문 / 바탕", SnapColor.ink, SnapColor.background),
    TextPair("본문 / 카드", SnapColor.ink, SnapColor.card),
    TextPair("본문 / 블러시", SnapColor.ink, SnapColor.blush),
    TextPair("보조 글자 / 바탕", SnapColor.inkSecondary, SnapColor.background),
    TextPair("보조 글자 / 카드", SnapColor.inkSecondary, SnapColor.card),
    TextPair("보조 글자 / 중립 면", SnapColor.inkSecondary, SnapColor.neutral),
    TextPair("강조색 / 바탕", SnapColor.accent, SnapColor.background),
    TextPair("강조색 / 카드", SnapColor.accent, SnapColor.card),
    TextPair("보조 버튼: 강조색 / 블러시", SnapColor.accent, SnapColor.blush),
    TextPair("채운 버튼: onAccent / 강조색", SnapColor.onAccent, SnapColor.accent),
    TextPair("라일락 글자 / 라일락 면", SnapColor.lilacText, SnapColor.lilacSoft),
    TextPair("라일락 글자 / 카드", SnapColor.lilacText, SnapColor.card),
    TextPair("삭제 보조 버튼: 경고 / 경고 면", SnapColor.danger, SnapColor.dangerSoft),
    TextPair("삭제 채운 버튼: onAccent / 경고", SnapColor.onAccent, SnapColor.danger),
    TextPair("막대 삭제 버튼: 경고 / 바탕", SnapColor.danger, SnapColor.background),
  ]

  @Test("글자 조합은 라이트·다크 모두 대비 4.5:1 이상이다", arguments: Self.textPairs.map(\.name))
  func textPairMeetsContrast(name: String) throws {
    let pair = try #require(Self.textPairs.first { $0.name == name })
    #expect(Self.contrast(pair.text.light, pair.background.light) >= 4.5, "라이트 \(name)")
    #expect(Self.contrast(pair.text.dark, pair.background.dark) >= 4.5, "다크 \(name)")
  }

  @Test("면용 로즈는 글자 대비에 못 미쳐 강조색과 따로 둔다")
  func roseIsDecorativeOnly() {
    #expect(Self.contrast(SnapColor.rose.light, SnapColor.background.light) < 4.5)
    #expect(SnapColor.accent != SnapColor.rose)
  }

  @Test("카테고리 아이콘의 선은 칸 바탕과 구분된다(그래픽 대비 2.5:1 이상, 라벨이 함께 보인다)")
  func glyphLineStandsOutFromTile() {
    for glyph in SnapGlyph.allCases {
      let palette = glyph.palette
      #expect(Self.contrast(palette.line.light, palette.tile.light) >= 2.5, "\(glyph) 라이트")
      #expect(Self.contrast(palette.line.dark, palette.tile.dark) >= 2.5, "\(glyph) 다크")
    }
  }

  @Test("진행 막대 채움은 트랙과 구분된다(그래픽 대비 3:1 이상)", arguments: SnapProgressStyle.Tint.allCases)
  func progressFillStandsOutFromTrack(tint: SnapProgressStyle.Tint) {
    #expect(Self.contrast(tint.fill.light, tint.track.light) >= 3, "\(tint) 라이트")
    #expect(Self.contrast(tint.fill.dark, tint.track.dark) >= 3, "\(tint) 다크")
  }

  @Test("로딩 점은 적어도 두 개가 바탕·카드와 구분된다(그래픽 대비 3:1 이상)")
  func loadingDotsStandOut() {
    let surfaces = [SnapColor.background, SnapColor.card]
    let visible = SnapLoadingDots.colors.filter { dot in
      surfaces.allSatisfy { surface in
        Self.contrast(dot.light, surface.light) >= 3 && Self.contrast(dot.dark, surface.dark) >= 3
      }
    }
    #expect(visible.count >= 2)
  }

  @Test("아이콘마다 칸 색이 다르다")
  func glyphTilesAreDistinct() {
    let tiles = Set(SnapGlyph.allCases.map(\.palette.tile))
    #expect(tiles.count == SnapGlyph.allCases.count)
  }

  /// WCAG 2 상대 휘도 대비.
  static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
    let lighter = max(self.luminance(first), self.luminance(second))
    let darker = min(self.luminance(first), self.luminance(second))
    return (lighter + 0.05) / (darker + 0.05)
  }

  static func luminance(_ hex: UInt32) -> Double {
    func channel(_ shift: UInt32) -> Double {
      let value = Double((hex >> shift) & 0xFF) / 255
      return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
  }
}
