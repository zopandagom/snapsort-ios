import Core
import Testing

struct ImageCategoryTests {
  @Test(
    "카테고리를 정보형·사진형·기타로 나눈다",
    arguments: [
      (ImageCategory.gifticon, ImageCategoryGroup.information),
      (.receipt, .information),
      (.chat, .information),
      (.shopping, .information),
      (.map, .information),
      (.document, .information),
      (.travel, .photo),
      (.food, .photo),
      (.people, .photo),
      (.pet, .photo),
      (.landscape, .photo),
      (.other, .other),
    ]
  )
  func groupsCategory(category: ImageCategory, expected: ImageCategoryGroup) {
    #expect(category.group == expected)
  }

  @Test("저장 키로 쓰는 rawValue 가 바뀌지 않는다")
  func keepsRawValues() {
    #expect(ImageCategory.allCases.map(\.rawValue) == [
      "gifticon", "receipt", "chat", "shopping", "map", "document",
      "travel", "food", "people", "pet", "landscape",
      "other",
    ])
  }
}
