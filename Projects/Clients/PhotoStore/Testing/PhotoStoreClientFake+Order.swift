import Core
import PhotoStoreInterface

// 정렬·판정 순수 함수. 잠금 밖에서도 안에서도 부를 수 있게 상태를 읽지 않는다.
extension PhotoStoreClientFake {
  /// 최신순. 생성일이 없으면 맨 뒤, 같으면 식별자 순으로 고정한다.
  static func isNewer(_ lhs: IndexedImage, than rhs: IndexedImage) -> Bool {
    switch (lhs.asset.creationDate, rhs.asset.creationDate) {
    case let (left?, right?) where left != right:
      left > right
    case (.some, nil):
      true
    case (nil, .some):
      false
    default:
      lhs.id < rhs.id
    }
  }

  /// 그 카테고리 이미지를 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로.
  /// Impl 처럼 `.travel` 은 이미지 카테고리로 다루지 않아 빈 배열이다.
  static func sortedImages(_ images: some Sequence<IndexedImage>, in category: ImageCategory) -> [IndexedImage] {
    guard category != .travel else {
      return []
    }
    return images.filter { $0.categories.contains(category) }.sorted(by: self.isNewer)
  }

  /// 기프티콘으로 분류돼 글자를 읽었는데 추출 값이 없다.
  static func isGifticonExtractionPending(_ image: IndexedImage) -> Bool {
    image.categories.contains(.gifticon) && image.textLines != nil && image.gifticon == nil
  }
}
