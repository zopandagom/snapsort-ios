/// 언어 모델이 제안한 카테고리 중 OCR 원문에 근거가 있는 정보형만 고른다 (docs/ARCHITECTURE.md §4 분류).
/// 규칙 분류가 기타뿐인 이미지에만 쓴다. 근거는 규칙 기준보다 약하다(규칙은 키워드 2개, 이것은 1개).
/// 모델은 밈·지시문 텍스트에도 기프티콘·지도를 붙이므로 근거 없는 제안은 버린다. 사진형·여행은 텍스트로 정하지 않아 받지 않는다.
/// 근거 기준은 임시 값이며 정확도 측정 작업에서 조정한다.
public enum ModelCategoryPolicy {
  /// 기프티콘·영수증·쇼핑·지도로 받는 데 필요한 그 카테고리 키워드 수(`ClassificationRules.informationRules`).
  /// 임시, 정확도 측정 작업에서 조정.
  static let minimumKeywordMatches = 1
  /// 대화로 받는 데 필요한 말풍선 시각 줄 수(줄 전체가 `chatTimestampPattern`). 규칙과 달리 시각 순서는 보지 않는다.
  /// 임시, 정확도 측정 작업에서 조정.
  static let minimumChatTimestampLines = 1

  /// `proposed` 중 근거가 있는 정보형. 문서는 공백 뺀 글자가 `ClassificationRules.minimumDocumentTextLength` 이상일 때만 받는다.
  public static func accepted(_ proposed: Set<ImageCategory>, textLines: [RecognizedTextLine]) -> Set<ImageCategory> {
    let keywordLines = textLines.map { KeywordLine($0.text) }
    let normalizedLines = textLines.map { ClassificationRules.normalize($0.text) }
    let timestampPattern = ClassificationRules.chatTimestampPattern
    let timestampLineCount = normalizedLines.count { $0.wholeMatch(of: timestampPattern) != nil }
    let textLength = normalizedLines.reduce(0) { $0 + $1.count }
    return proposed.filter { category in
      switch category {
      case .gifticon, .receipt, .shopping, .map:
        self.keywordMatches(for: category, in: keywordLines) >= self.minimumKeywordMatches
      case .chat:
        timestampLineCount >= self.minimumChatTimestampLines
      case .document:
        textLength >= ClassificationRules.minimumDocumentTextLength
      case .travel, .food, .people, .pet, .landscape, .other:
        false
      }
    }
  }

  /// OCR 줄에 나온 `category` 규칙 키워드 수. 규칙 분류와 같은 방법(`KeywordLine`)으로 대조한다.
  private static func keywordMatches(for category: ImageCategory, in keywordLines: [KeywordLine]) -> Int {
    let keywords = ClassificationRules.informationRules.first { $0.category == category }?.keywords ?? []
    return keywords.count { keyword in keywordLines.contains { $0.contains(keyword) } }
  }
}
