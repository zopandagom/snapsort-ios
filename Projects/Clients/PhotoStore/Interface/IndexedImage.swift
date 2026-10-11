import Core

/// 분류 파이프라인을 거친 이미지 한 장의 저장 단위 (docs/ARCHITECTURE.md §4).
/// 카테고리와 함께 그 근거인 라벨·OCR 줄을 남겨, 분류 규칙을 바꿔도 Vision 을 다시 돌리지 않고 카테고리를 다시 정할 수 있게 한다.
public struct IndexedImage: Sendable, Hashable, Identifiable {
  public let asset: ImageAsset
  /// Vision 이미지 분류 라벨.
  public let labels: [ImageLabel]
  /// OCR 로 읽은 줄. OCR 대상이 아니어서 읽지 않았으면 nil, 읽었는데 글자가 없으면 빈 배열이다.
  public let textLines: [RecognizedTextLine]?
  /// 규칙 분류기가 정한 카테고리. 여행은 여행 판정이 정해 `trips()` 로 다루므로, `.travel` 을 넣어도 저장하지 않는다.
  public let categories: Set<ImageCategory>

  public var id: ImageAsset.ID { self.asset.id }

  public init(
    asset: ImageAsset,
    labels: [ImageLabel],
    textLines: [RecognizedTextLine]?,
    categories: Set<ImageCategory>
  ) {
    self.asset = asset
    self.labels = labels
    self.textLines = textLines
    self.categories = categories
  }
}
