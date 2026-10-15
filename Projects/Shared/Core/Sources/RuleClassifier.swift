/// 이미지 한 장의 메타데이터·이미지 분류 라벨·OCR 텍스트로 카테고리를 고르는 키워드 규칙 분류기 (docs/ARCHITECTURE.md §4).
/// 모든 기기에서 동작하는 기본 분류다. Foundation Models 는 지원 기기에서 이 결과를 보강한다.
public enum RuleClassifier {
  /// 이미지가 속한 카테고리. 여러 개일 수 있고, 어디에도 해당하지 않으면 `[.other]` 다.
  /// - 정보형: 해당 라벨이 있거나 OCR 텍스트에 키워드가 기준 개수 이상 있으면. 문서는 라벨에 더해 OCR 글자가 기준 이상이어야 한다.
  ///   대화 캡처는 말풍선 시각 줄로도 판단한다.
  /// - 사진형: 스크린샷이 아닐 때만 라벨로 판단한다. 화면에 보이던 음식·인물은 사진형으로 묶지 않는다.
  ///   남이 보낸 스크린샷을 저장한 이미지처럼 메타데이터로는 모르는 경우를 위해 `screenshot` 라벨도 스크린샷으로 본다.
  ///   카테고리별 신뢰도 기준을 넘는 라벨만 쓰고, 그림(`drawingLabels`)이면 붙이지 않으며, 인물이 있으면 풍경은 붙이지 않는다.
  /// - 여행은 여러 장의 위치·날짜로 판정하므로 여기서 돌려주지 않는다.
  /// - Parameter textLines: OCR 하지 않았거나 아직 읽지 않은(인덱서 2단계 대기) 이미지는 빈 배열.
  ///   라벨이 같으면 빈 배열(OCR 전)의 결과에 줄을 더해도 `.other` 밖의 카테고리는 빠지지 않는다(인덱서가 대기 이미지의 카테고리를 먼저 저장하는 전제).
  ///   줄이 있는 결과끼리는 아니다: 대화 캡처는 시각 순서를 보므로 줄을 더하면 빠질 수 있다.
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
    if categories.contains(.document),
       normalizedLines.reduce(0, { $0 + $1.count }) < ClassificationRules.minimumDocumentTextLength
    {
      categories.remove(.document)
    }
    if self.isChat(normalizedLines: normalizedLines) {
      categories.insert(.chat)
    }
    let isScreenshot = asset.isScreenshot || identifiers.contains(ClassificationRules.screenshotLabel)
    if !isScreenshot {
      categories.formUnion(self.photoCategories(labels: labels))
    }
    return categories.isEmpty ? [.other] : categories
  }

  /// 라벨로 정한 사진형 카테고리(스크린샷 여부는 보지 않는다). OCR 대상 판정(`TextRecognitionPolicy`)도 같은 기준을 쓴다.
  static func photoCategories(labels: [ImageLabel]) -> Set<ImageCategory> {
    let isDrawing = labels.contains {
      ClassificationRules.drawingLabels.contains($0.identifier)
        && $0.confidence >= ClassificationRules.drawingMinimumConfidence
    }
    guard !isDrawing else { return [] }
    var categories = Set<ImageCategory>()
    for (category, photoLabels) in ClassificationRules.photoLabels {
      let minimum = ClassificationRules.photoLabelMinimumConfidence[category]
        ?? ClassificationRules.minimumLabelConfidence
      if labels.contains(where: { photoLabels.contains($0.identifier) && $0.confidence >= minimum }) {
        categories.insert(category)
      }
    }
    if categories.contains(.people) {
      categories.remove(.landscape)
    }
    return categories
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

  /// 말풍선 시각 줄이 기준 이상이고, 이웃한 시각끼리 늘거나 같은 쌍이 줄어드는 쌍보다 많으면 대화 캡처다.
  /// OCR 이 좌우 말풍선의 줄 순서를 조금 섞어 읽어도 대체로 오름차순이면 인정한다. 자정을 넘긴 쌍은 늘어난 쌍으로 센다.
  private static func isChat(normalizedLines: [String]) -> Bool {
    let pattern = ClassificationRules.chatTimestampPattern
    let minutes = normalizedLines.compactMap { line in
      line.wholeMatch(of: pattern) != nil ? self.minutesOfDay(timestampLine: line) : nil
    }
    guard minutes.count >= ClassificationRules.minimumChatTimestampLines else { return false }
    let rising = zip(minutes, minutes.dropFirst()).count { $0 <= $1 || self.crossesMidnight(from: $0, to: $1) }
    return rising > minutes.count - 1 - rising
  }

  /// 오후 10시 이후에서 오전 2시 전으로 넘어가면 자정을 넘긴 대화로 보고 늘어난 쌍으로 센다.
  private static func crossesMidnight(from earlier: Int, to later: Int) -> Bool {
    earlier >= 22 * 60 && later < 2 * 60
  }

  /// `chatTimestampPattern` 에 맞는 줄("1오후3:12", "오전11:182")의 자정부터 분. 오전·오후 뒤 시와 콜론 뒤 두 자리만 읽는다.
  private static func minutesOfDay(timestampLine line: String) -> Int? {
    guard let marker = line.range(of: "오전") ?? line.range(of: "오후") else { return nil }
    let parts = line[marker.upperBound...].split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1].prefix(2)) else { return nil }
    let isAfternoon = line[marker] == "오후"
    return (hour % 12 + (isAfternoon ? 12 : 0)) * 60 + minute
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
