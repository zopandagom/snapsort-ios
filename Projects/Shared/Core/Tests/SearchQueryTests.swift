import Testing
@testable import Core

struct SearchQueryTests {
  @Test("공백(U+3000·NBSP 포함)으로 낱말을 나누고 낱말마다 소문자로 정규화한다")
  func splitsOnWhitespaceAndLowercases() {
    #expect(SearchQuery("Coupang\u{3000}Nike\u{00A0}운동화\n신발").words == ["coupang", "nike", "운동화", "신발"])
  }

  @Test("분해된 한글 입력은 NFC 로 바꾼다")
  func normalizesToNFC() {
    let decomposed = "쿠팡".decomposedStringWithCanonicalMapping
    let composed = "쿠팡".precomposedStringWithCanonicalMapping
    // String 의 == 는 정준 동등이라 분해·조합이 같게 나온다. 스칼라로 비교한다.
    #expect(Array(decomposed.unicodeScalars) != Array(composed.unicodeScalars))
    #expect(SearchQuery(decomposed).words.map { Array($0.unicodeScalars) } == [Array(composed.unicodeScalars)])
    #expect(Array(SearchText.normalize(decomposed).unicodeScalars) == Array(composed.unicodeScalars))
  }

  @Test("정규화는 소문자로 바꾸고 공백을 지운다")
  func normalizeRemovesWhitespace() {
    #expect(SearchText.normalize(" A b\u{3000}C ") == "abc")
  }

  @Test("같은 낱말은 처음 것만 두고 순서를 지킨다")
  func removesDuplicates() {
    #expect(SearchQuery("b A B a c").words == ["b", "a", "c"])
  }

  @Test("공백만이거나 빈 문자열이면 빈 검색어다")
  func blankIsEmpty() {
    #expect(SearchQuery("").isEmpty)
    #expect(SearchQuery(" \u{3000}\n ").isEmpty)
    #expect(SearchQuery("").words.isEmpty)
    #expect(!SearchQuery("a").isEmpty)
  }

  @Test("matches(name:) 은 낱말이 모두 들어 있으면 참이고 순서와 상관없다")
  func matchesNameWithAllWords() {
    #expect(SearchQuery("기프").matches(name: "기프티콘"))
    #expect(SearchQuery("콘 기프").matches(name: "기프티콘"))
    #expect(SearchQuery("서울 강남").matches(name: "서울특별시 강남구"))
    #expect(!SearchQuery("기프 영수증").matches(name: "기프티콘"))
  }

  @Test("matches(name:) 은 대소문자와 공백을 무시하고 빈 검색어는 거짓이다")
  func matchesNameNormalizes() {
    #expect(SearchQuery("TRIP").matches(name: "Trip 폴더"))
    #expect(SearchQuery("제주 시").matches(name: "제주시"))
    #expect(!SearchQuery("").matches(name: "기프티콘"))
    #expect(!SearchQuery("  ").matches(name: ""))
  }
}
