import Core

/// 분류 파이프라인을 거친 이미지 한 장의 저장 단위 (docs/ARCHITECTURE.md §4).
/// 카테고리와 함께 그 근거인 라벨·OCR 줄을 남겨, 분류 규칙을 바꿔도 Vision 을 다시 돌리지 않고 카테고리를 다시 정할 수 있게 한다.
public struct IndexedImage: Sendable, Hashable, Identifiable {
  public let asset: ImageAsset
  /// Vision 이미지 분류 라벨.
  public let labels: [ImageLabel]
  /// OCR 상태. 인덱서는 분류를 먼저 저장하고(OCR 대상은 `.pending`) 글자는 나중에 읽어 `.recognized` 로 바꾼다.
  public let textRecognition: TextRecognition
  /// 규칙 분류기가 정한 카테고리. 여행은 여행 판정이 정해 `trips()` 로 다루므로, `.travel` 을 넣어도 저장하지 않는다.
  /// `.pending` 이면 라벨만으로 나온 카테고리에서 `.other` 를 뺀 것이다(글자를 읽으면 더해지기만 한다).
  public let categories: Set<ImageCategory>

  public var id: ImageAsset.ID { self.asset.id }

  /// 읽은 줄. 읽지 않았으면(OCR 대상 아님·대기) nil, 읽었는데 글자가 없으면 빈 배열이다.
  public var textLines: [RecognizedTextLine]? {
    if case let .recognized(lines) = self.textRecognition {
      return lines
    }
    return nil
  }

  public init(
    asset: ImageAsset,
    labels: [ImageLabel],
    textRecognition: TextRecognition,
    categories: Set<ImageCategory>
  ) {
    self.asset = asset
    self.labels = labels
    self.textRecognition = textRecognition
    self.categories = categories
  }
}

/// OCR 상태. 분류 파이프라인 ③단계 (docs/ARCHITECTURE.md §4).
public enum TextRecognition: Sendable, Hashable {
  /// OCR 대상이 아니다.
  case notNeeded
  /// OCR 대상인데 아직 읽지 않았다(인덱서 2단계 대기).
  case pending
  /// 읽었다. 글자가 없으면 빈 배열.
  case recognized([RecognizedTextLine])
}
