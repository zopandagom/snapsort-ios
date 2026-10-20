import Core
import CoreGraphics
import Testing

/// 테스트의 OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct ModelCategoryPolicyTests {
  @Test("근거 키워드가 없는 모델 카테고리는 버린다")
  func dropsCategoriesWithoutKeyword() {
    let lines = [line("오늘 점심 뭐 먹지"), line("ㅋㅋㅋ 진짜 웃기다")]

    #expect(ModelCategoryPolicy.accepted([.gifticon, .receipt, .shopping, .map], textLines: lines).isEmpty)
  }

  @Test(
    "그 카테고리 키워드가 하나 있으면 더한다",
    arguments: [
      (ImageCategory.gifticon, "모바일 교환권"),
      (.receipt, "합계 12,000"),
      (.shopping, "장바구니 담기"),
      (.map, "길찾기"),
    ]
  )
  func acceptsCategoryWithOneKeyword(category: ImageCategory, text: String) {
    let lines = [line("오늘 점심 뭐 먹지"), line(text)]
    let others = Set<ImageCategory>([.gifticon, .receipt, .shopping, .map]).subtracting([category])

    #expect(ModelCategoryPolicy.accepted([category], textLines: lines) == [category])
    #expect(ModelCategoryPolicy.accepted(others.union([category]), textLines: lines) == [category])
  }

  @Test("대화는 말풍선 시각 줄이 하나 이상일 때만 더한다")
  func acceptsChatWithTimestampLine() {
    let timestamp = [line("내일 몇 시에 볼까"), line("오후 3:12")]
    let sentence = [line("내일 미사 오전 11:30 에 보자")]

    #expect(ModelCategoryPolicy.accepted([.chat], textLines: timestamp) == [.chat])
    #expect(ModelCategoryPolicy.accepted([.chat], textLines: sentence).isEmpty)
  }

  @Test("문서는 글자가 기준 이상일 때만 더한다")
  func acceptsDocumentWithEnoughText() {
    let text = String(repeating: "가", count: 30)

    #expect(ModelCategoryPolicy.accepted([.document], textLines: [line(text)]) == [.document])
    #expect(ModelCategoryPolicy.accepted([.document], textLines: [line(String(text.dropFirst()))]).isEmpty)
  }

  @Test("사진형·여행·기타 제안은 버린다")
  func dropsNonInformationCategories() {
    let lines = [line("교환권 합계 장바구니 길찾기 오후 3:12"), line(String(repeating: "가", count: 30))]

    #expect(ModelCategoryPolicy.accepted([.food, .people, .pet, .landscape, .travel, .other], textLines: lines).isEmpty)
  }
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.03))
}
