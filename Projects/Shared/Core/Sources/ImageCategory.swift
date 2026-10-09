/// 이미지 분류 카테고리. 한 이미지가 여러 카테고리에 속할 수 있다 (docs/ARCHITECTURE.md §4).
/// rawValue 는 분류 결과 저장 키로 쓰이므로 이름을 바꾸지 않는다.
public enum ImageCategory: String, Sendable, Hashable, Codable, CaseIterable {
  case gifticon
  case receipt
  case chat
  case shopping
  case map
  case document

  case travel
  case food
  case people
  case pet
  case landscape

  case other

  /// 정보형(캡처·저장 이미지에서 텍스트로 판단)인지 사진형(촬영 사진)인지.
  public var group: ImageCategoryGroup {
    switch self {
    case .gifticon, .receipt, .chat, .shopping, .map, .document:
      .information
    case .travel, .food, .people, .pet, .landscape:
      .photo
    case .other:
      .other
    }
  }
}

public enum ImageCategoryGroup: Sendable, Hashable {
  case information
  case photo
  case other
}
