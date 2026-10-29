import Testing
@testable import Core

/// 교환처 브랜드 목록의 별칭 규칙. 어기면 그 브랜드가 대조되지 않거나 다른 브랜드와 같은 교환처가 되는데 오류가 나지 않는다.
struct GifticonBrandTests {
  @Test("별칭은 정규화한 꼴(소문자, 공백 없음)이다")
  func aliasesAreNormalized() {
    for alias in GifticonBrand.all.joined() {
      #expect(GifticonExtractor.compact(alias).lowercased() == alias, "\(alias)")
    }
  }

  @Test("별칭은 브랜드 사이에서도 겹치지 않는다")
  func aliasesAreUnique() {
    let aliases = Array(GifticonBrand.all.joined())
    #expect(Set(aliases).count == aliases.count)
  }

  @Test("모든 별칭이 자기 브랜드를 찾는다")
  func aliasesFindOwnBrand() {
    for (index, aliases) in GifticonBrand.all.enumerated() {
      for alias in aliases {
        #expect(GifticonBrand.index(of: alias) == index, "\(alias)")
      }
    }
  }
}
