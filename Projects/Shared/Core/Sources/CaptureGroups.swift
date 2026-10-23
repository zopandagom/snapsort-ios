/// 쇼핑·대화·지도 캡처에서 찾은 묶음 값 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). 닫힌 목록의 값만 담고 OCR 텍스트는 담지 않는다.
/// 그래도 사진에서 읽은 것에서 나온 값이라 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct CaptureGroups: Sendable, Hashable {
  /// 쇼핑몰. 쇼핑 카테고리에서 찾고, 못 찾으면 nil.
  public let mall: ShoppingMall?
  public let brand: ShoppingBrand?
  /// 대화 앱. 대화 카테고리에서 찾고, 못 찾으면 nil.
  public let chatApp: ChatApp?
  /// 지도 캡처의 지역. 비면 지역 모름. 서로 다른 지역이 여럿 나오면 모두 담는다.
  public let regions: Set<KoreanRegion>

  public init(
    mall: ShoppingMall? = nil,
    brand: ShoppingBrand? = nil,
    chatApp: ChatApp? = nil,
    regions: Set<KoreanRegion> = []
  ) {
    self.mall = mall
    self.brand = brand
    self.chatApp = chatApp
    self.regions = regions
  }

  /// 추출했지만 아무 값도 찾지 못함.
  public static let empty = CaptureGroups()

  /// 그 카테고리에 없는 필드를 비운다: 쇼핑이 아니면 mall·brand nil, 대화가 아니면 chatApp nil, 지도가 아니면 regions 빈 집합.
  public func restricted(to categories: Set<ImageCategory>) -> CaptureGroups {
    let isShopping = categories.contains(.shopping)
    return CaptureGroups(
      mall: isShopping ? self.mall : nil,
      brand: isShopping ? self.brand : nil,
      chatApp: categories.contains(.chat) ? self.chatApp : nil,
      regions: categories.contains(.map) ? self.regions : []
    )
  }
}
