import Core
import DesignSystem
import Testing
@testable import LibraryFeature

struct ImageCategoryGlyphTests {
  @Test("카테고리 12종은 모두 서로 다른 직접 그린 아이콘을 쓴다")
  func everyCategoryHasItsOwnGlyph() {
    let glyphs = ImageCategory.allCases.map(\.glyph)
    #expect(Set(glyphs).count == ImageCategory.allCases.count)
    #expect(Set(glyphs) == Set(SnapGlyph.allCases))
  }
}
