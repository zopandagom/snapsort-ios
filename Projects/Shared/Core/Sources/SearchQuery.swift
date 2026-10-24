import Foundation

/// 검색 정규화 (docs/ARCHITECTURE.md §4 검색). 검색어와 대조 대상 모두 이것으로 바꾼다.
public enum SearchText {
  /// `ClassificationRules.normalize`(소문자, 공백(`Character.isWhitespace`: U+3000·NBSP·줄바꿈 포함) 제거) 뒤 NFC.
  public static func normalize(_ text: String) -> String {
    ClassificationRules.normalize(text).precomposedStringWithCanonicalMapping
  }
}

/// 검색어. 원문을 공백으로 나눈 낱말마다 정규화한 값. 빈 낱말은 빼고 같은 낱말은 처음 것만 둔다(순서 유지).
/// 검색어는 사용자 입력이라 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct SearchQuery: Sendable, Hashable {
  public let words: [String]

  public init(_ text: String) {
    var seen: Set<String> = []
    self.words = text.split(whereSeparator: \.isWhitespace)
      .map { SearchText.normalize(String($0)) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  public var isEmpty: Bool {
    self.words.isEmpty
  }

  /// 정규화한 name 안에 낱말이 모두 들어 있으면 참(포함, 순서 무관). 카테고리 이름·장소 이름 대조에 쓴다. 빈 검색어는 거짓.
  public func matches(name: String) -> Bool {
    guard !self.isEmpty else { return false }
    let normalized = SearchText.normalize(name)
    return self.words.allSatisfy { normalized.range(of: $0, options: .literal) != nil }
  }
}
