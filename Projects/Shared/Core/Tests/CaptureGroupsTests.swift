import Core
import Testing

struct CaptureGroupsTests {
  private static let all = CaptureGroups(
    mall: ShoppingMall(id: "coupang"),
    brand: ShoppingBrand(id: "nike"),
    chatApp: .kakaoTalk,
    regions: [KoreanRegion(id: "seoul:강남구")!]
  )

  private static let restrictCases: [(Set<ImageCategory>, CaptureGroups)] = [
    ([.shopping], CaptureGroups(mall: ShoppingMall(id: "coupang"), brand: ShoppingBrand(id: "nike"))),
    ([.chat], CaptureGroups(chatApp: .kakaoTalk)),
    ([.map], CaptureGroups(regions: [KoreanRegion(id: "seoul:강남구")!])),
    ([.chat, .map], CaptureGroups(chatApp: .kakaoTalk, regions: [KoreanRegion(id: "seoul:강남구")!])),
    ([.document, .receipt], .empty),
    ([], .empty),
  ]

  @Test("restricted(to:) 는 그 카테고리에 없는 필드를 비운다", arguments: restrictCases)
  func restrictsFields(_ categories: Set<ImageCategory>, _ expected: CaptureGroups) {
    #expect(Self.all.restricted(to: categories) == expected)
  }

  @Test("묶음을 찾는 카테고리는 쇼핑·대화·지도다")
  func extractorCategories() {
    #expect(CaptureGroupExtractor.categories == [.shopping, .chat, .map])
    #expect(CaptureGroupExtractor.rulesVersion == 1)
  }

  @Test("extract 는 restricted 와 같은 결과이고 줄이 없으면 빈 값이다")
  func extractMatchesRestricted() {
    let lines = ["쿠팡", "나이키", "여기까지 읽었습니다", "서울 강남구"].map {
      RecognizedTextLine(text: $0, confidence: 0.9, boundingBox: .init(x: 0, y: 0, width: 1, height: 0.1))
    }
    let everything = CaptureGroupExtractor.extract(from: lines, categories: [.shopping, .chat, .map])

    #expect(everything == Self.all)
    for categories: Set<ImageCategory> in [[.shopping], [.chat], [.map], [.chat, .map], [.document]] {
      #expect(CaptureGroupExtractor.extract(from: lines, categories: categories) == everything
        .restricted(to: categories))
    }
    #expect(CaptureGroupExtractor.extract(from: [], categories: [.shopping, .chat, .map]) == .empty)
  }
}
