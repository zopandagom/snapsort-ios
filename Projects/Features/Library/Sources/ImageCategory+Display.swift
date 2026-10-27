import Core
import DesignSystem

/// 화면에 보이는 이름과 아이콘. Core 는 SwiftUI·문구를 갖지 않으므로 화면 쪽에 둔다.
extension ImageCategory {
  var title: String {
    switch self {
    case .gifticon: "기프티콘"
    case .receipt: "영수증"
    case .chat: "대화 캡처"
    case .shopping: "쇼핑"
    case .map: "지도"
    case .document: "문서·메모"
    case .travel: "여행"
    case .food: "음식"
    case .people: "인물"
    case .pet: "반려동물"
    case .landscape: "풍경"
    case .other: "기타"
    }
  }

  /// 직접 그린 카테고리 아이콘 (DesignSystem `SnapGlyph`).
  var glyph: SnapGlyph {
    switch self {
    case .gifticon: .gift
    case .receipt: .receipt
    case .chat: .chatBubble
    case .shopping: .shoppingBag
    case .map: .mapPin
    case .document: .document
    case .travel: .suitcase
    case .food: .bowl
    case .people: .person
    case .pet: .paw
    case .landscape: .mountain
    case .other: .grid
    }
  }

  /// SF Symbols 만 받는 곳(지도 `Marker`, 썸네일 칸의 대체 표시)에 쓰는 심볼.
  var systemImage: String {
    switch self {
    case .gifticon: "gift"
    case .receipt: "receipt"
    case .chat: "bubble.left.and.bubble.right"
    case .shopping: "bag"
    case .map: "map"
    case .document: "doc.text"
    case .travel: "airplane"
    case .food: "fork.knife"
    case .people: "person.2"
    case .pet: "pawprint"
    case .landscape: "mountain.2"
    case .other: "square.grid.2x2"
    }
  }

  /// 여행은 이미지 수가 아니라 여행 수를 센다 (`LibraryModel.categoryCounts`).
  func countText(_ count: Int) -> String {
    self == .travel ? "\(count)번" : "\(count)장"
  }
}
