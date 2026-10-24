import Foundation

/// 메모리 검색 색인 (docs/ARCHITECTURE.md §4 검색). 만드는 데 1만 장 × 20줄에서 수백 ms 라 메인 밖에서 만든다(부르는 쪽 책임).
/// OCR 텍스트를 담으므로 로그에 남기지 않는다.
public struct SearchIndex: Sendable {
  private struct Item: Sendable {
    let entry: SearchEntry
    /// 줄마다 정규화한 UTF-8 을 `0x0A` 로 이은 바이트. 정규화가 공백(줄바꿈 포함)을 지우고 0x0A 는 여러 바이트 글자 안에
    /// 나오지 않으므로(모두 0x80 이상) 이어 붙여도 낱말이 줄을 넘어 맞지 않는다. 빈 줄도 이어 붙여 줄 번호가 맞는다.
    let text: [UInt8]
    /// `termLists` 의 번호. 0 은 묶음 값 별칭 없음.
    let termList: Int
  }

  private let items: [Item]
  /// 서로 다른 묶음 값마다 한 번만 만든 별칭 목록. 0 번은 빈 목록.
  private let termLists: [[SearchTerm]]

  /// entries 순서를 결과 순서로 쓴다(저장소가 최신순으로 준다).
  /// previous 에 같은 식별자·같은 줄(`lines ==`)의 항목이 있으면 그 정규화 바이트(`text`)만 다시 쓴다(다시 읽기마다 전체를 다시 정규화하지 않게).
  /// 별칭 목록 번호는 항상 이번 `termLists` 에서 다시 매긴다(옛 번호는 다른 목록을 가리킬 수 있다).
  public init(entries: [SearchEntry], reusing previous: SearchIndex? = nil) {
    let old: [ImageAsset.ID: Item] = if let previous {
      Dictionary(previous.items.map { ($0.entry.id, $0) }, uniquingKeysWith: { first, _ in first })
    } else {
      [:]
    }
    var lists: [[SearchTerm]] = [[]]
    var listNumbers: [String: Int] = [:]
    self.items = entries.map { entry in
      let reused = old[entry.id].flatMap { $0.entry.lines == entry.lines ? $0 : nil }
      let text = reused?.text ?? Array(entry.lines.map(SearchText.normalize).joined(separator: "\n").utf8)
      var termList = 0
      if let groups = entry.captureGroups {
        let key = groups.searchKey
        if let number = listNumbers[key] {
          termList = number
        } else {
          let terms = groups.searchTerms
          if !terms.isEmpty {
            lists.append(terms)
            termList = lists.count - 1
          }
          listNumbers[key] = termList
        }
      }
      return Item(entry: entry, text: text, termList: termList)
    }
    self.termLists = lists
  }

  public var count: Int {
    self.items.count
  }

  /// 낱말이 모두 그 이미지에 있는 이미지를 entries 순서로. 빈 검색어는 빈 배열.
  /// 대조는 정규화한 UTF-8 바이트 부분 일치(유니코드 스칼라 단위)라 이모지 조합처럼 한 글자 안에서도 맞을 수 있다.
  public func hits(for query: SearchQuery) -> [SearchHit] {
    guard !query.isEmpty else { return [] }
    let words = query.words.map { Array($0.utf8) }
    // 낱말마다 목록마다 처음 맞는 별칭의 표 이름 (낱말 수 × 목록 수).
    let titles: [[String?]] = words.map { word in
      self.termLists.map { list in list.first { Self.find(word, in: $0.bytes) != nil }?.title }
    }
    return self.items.compactMap { Self.hit(of: $0, words: words, titles: titles) }
  }

  private static func hit(of item: Item, words: [[UInt8]], titles: [[String?]]) -> SearchHit? {
    var firstPosition: Int?
    var firstGroupTitle: String?
    for (index, word) in words.enumerated() {
      if let position = Self.find(word, in: item.text) {
        firstPosition = min(firstPosition ?? position, position)
      } else if item.termList > 0, let title = titles[index][item.termList] {
        firstGroupTitle = firstGroupTitle ?? title
      } else {
        return nil
      }
    }
    let match: SearchMatch
    if let firstPosition {
      match = .line(item.entry.lines[Self.lineNumber(at: firstPosition, in: item.text)])
    } else if let firstGroupTitle {
      match = .group(firstGroupTitle)
    } else {
      return nil
    }
    return SearchHit(asset: item.entry.asset, match: match)
  }

  /// word 가 haystack 안에서 처음 맞는 바이트 위치. 올바른 UTF-8 끼리라 맞으면 스칼라 경계에서 시작·끝난다.
  private static func find(_ word: [UInt8], in haystack: [UInt8]) -> Int? {
    guard !word.isEmpty, haystack.count >= word.count else { return nil }
    return haystack.withUnsafeBytes { hay in
      word.withUnsafeBytes { needle in
        guard let base = hay.baseAddress,
              let found = memmem(base, hay.count, needle.baseAddress, needle.count) else { return nil }
        return base.distance(to: UnsafeRawPointer(found))
      }
    }
  }

  /// position 앞 0x0A 수 = 줄 번호.
  private static func lineNumber(at position: Int, in text: [UInt8]) -> Int {
    text.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { return 0 }
      var count = 0
      var offset = 0
      while offset < position, let found = memchr(base + offset, 10, position - offset) {
        count += 1
        offset = base.distance(to: UnsafeRawPointer(found)) + 1
      }
      return count
    }
  }
}

public struct SearchHit: Sendable, Hashable, Identifiable {
  public let asset: ImageAsset
  public let match: SearchMatch

  public var id: ImageAsset.ID {
    self.asset.id
  }

  public init(asset: ImageAsset, match: SearchMatch) {
    self.asset = asset
    self.match = match
  }
}

/// 결과 줄에 보일 맞은 곳.
public enum SearchMatch: Sendable, Hashable {
  /// 낱말이 줄에서 맞았다. 그 줄 원문(정규화 전).
  case line(String)
  /// 모든 낱말이 묶음 값 별칭에서만 맞았다. 표의 이름(예: "쿠팡", "서울 강남구").
  case group(String)
}
