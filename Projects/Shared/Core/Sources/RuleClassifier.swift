/// 이미지 한 장의 메타데이터·이미지 분류 라벨·OCR 텍스트로 카테고리를 고르는 키워드 규칙 분류기 (docs/ARCHITECTURE.md §4).
/// 모든 기기에서 동작하는 기본 분류다. Foundation Models 는 지원 기기에서 이 결과를 보강한다.
public enum RuleClassifier {
  /// 이미지가 속한 카테고리. 여러 개일 수 있고, 어디에도 해당하지 않으면 `[.other]` 다.
  /// - 정보형: 해당 라벨이 있거나 OCR 텍스트에 키워드가 기준 개수 이상 있으면. 대화 캡처는 말풍선 시각 줄로도 판단한다.
  /// - 사진형: 스크린샷이 아닐 때만 라벨로 판단한다. 화면에 보이던 음식·인물은 사진형으로 묶지 않는다.
  ///   남이 보낸 스크린샷을 저장한 이미지처럼 메타데이터로는 모르는 경우를 위해 `screenshot` 라벨도 스크린샷으로 본다.
  /// - 여행은 여러 장의 위치·날짜로 판정하므로 여기서 돌려주지 않는다.
  /// - Parameter textLines: OCR 하지 않았거나 아직 읽지 않은(인덱서 2단계 대기) 이미지는 빈 배열.
  ///   라벨이 같으면 줄을 더해도 `.other` 밖의 카테고리는 빠지지 않는다(인덱서가 대기 이미지의 카테고리를 먼저 저장하는 전제).
  public static func classify(
    asset: ImageAsset,
    labels: [ImageLabel],
    textLines: [RecognizedTextLine]
  ) -> Set<ImageCategory> {
    let identifiers = Set(labels.map(\.identifier))
    let keywordLines = textLines.map { KeywordLine($0.text) }
    let normalizedLines = textLines.map { ClassificationRules.normalize($0.text) }

    var categories = Set<ImageCategory>()
    for rule in ClassificationRules.informationRules
      where self.matches(rule, identifiers: identifiers, keywordLines: keywordLines)
    {
      categories.insert(rule.category)
    }
    if self.isChat(normalizedLines: normalizedLines) {
      categories.insert(.chat)
    }
    let isScreenshot = asset.isScreenshot || identifiers.contains(ClassificationRules.screenshotLabel)
    if !isScreenshot {
      for (category, photoLabels) in ClassificationRules.photoLabels where !identifiers.isDisjoint(with: photoLabels) {
        categories.insert(category)
      }
    }
    return categories.isEmpty ? [.other] : categories
  }

  private static func matches(
    _ rule: ClassificationRules.InformationRule,
    identifiers: Set<String>,
    keywordLines: [KeywordLine]
  ) -> Bool {
    if !identifiers.isDisjoint(with: rule.labels) {
      return true
    }
    guard !rule.keywords.isEmpty else { return false }
    let matchCount = rule.keywords.count { keyword in keywordLines.contains { $0.contains(keyword) } }
    return matchCount >= rule.minimumKeywordMatches
  }

  private static func isChat(normalizedLines: [String]) -> Bool {
    let pattern = ClassificationRules.chatTimestampPattern
    let timestampLines = normalizedLines.count { $0.contains(pattern) }
    return timestampLines >= ClassificationRules.minimumChatTimestampLines
  }
}

/// 키워드를 찾을 OCR 줄 하나. 공백을 지운 글자와 공백이 있던 자리를 함께 둔다.
/// OCR 이 "교 환 처", "유효 기간"처럼 띄워 읽어도 키워드를 찾되, "몇 시까지 도착해"의 "지도"처럼
/// 앞 단어 중간에서 시작해 공백을 넘어 걸린 것은 인정하지 않는다.
private struct KeywordLine {
  private let characters: [Character]
  /// 바로 앞에 공백이 있던 글자의 위치.
  private let spaceBefore: Set<Int>

  init(_ text: String) {
    var characters: [Character] = []
    var spaceBefore = Set<Int>()
    for character in text.lowercased() {
      if character.isWhitespace {
        spaceBefore.insert(characters.count)
      } else {
        characters.append(character)
      }
    }
    self.characters = characters
    self.spaceBefore = spaceBefore
  }

  func contains(_ keyword: String) -> Bool {
    let keyword = Array(keyword)
    guard !keyword.isEmpty, keyword.count <= self.characters.count else { return false }
    return (0 ... (self.characters.count - keyword.count)).contains { start in
      self.characters[start ..< start + keyword.count].elementsEqual(keyword)
        && self.isAligned(start: start, length: keyword.count)
    }
  }

  /// 공백을 넘지 않거나, 단어 시작에서 시작하면 인정한다.
  private func isAligned(start: Int, length: Int) -> Bool {
    let crossesSpace = self.spaceBefore.contains { start < $0 && $0 < start + length }
    return !crossesSpace || start == 0 || self.spaceBefore.contains(start)
  }
}
