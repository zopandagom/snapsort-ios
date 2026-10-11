import Testing
@testable import Core

struct ClassificationRulesTests {
  /// 대조 전에 OCR 텍스트를 정규화하므로, 공백이나 대문자가 든 키워드는 어떤 텍스트에도 걸리지 않는다.
  @Test("키워드는 정규화한 형태로 적는다", arguments: ClassificationRules.informationRules)
  func keywordsAreNormalized(rule: ClassificationRules.InformationRule) {
    for keyword in rule.keywords {
      #expect(ClassificationRules.normalize(keyword) == keyword, "\(rule.category) 키워드 \"\(keyword)\"")
    }
  }
}
