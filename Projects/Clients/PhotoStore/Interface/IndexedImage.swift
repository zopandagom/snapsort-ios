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
  /// 기프티콘 추출 값. nil 이면 추출하지 않았다(기프티콘 아님·OCR 전·지금 규칙 버전으로 추출 전).
  /// 추출했는데 못 찾은 값은 `GifticonInfo` 의 그 필드가 nil 이다.
  /// nil 은 "만료일 없음"이 아니다(규칙 버전을 올린 직후 소급 전에도 nil). 알림을 지우는 근거로 쓰지 않는다.
  /// 기프티콘 카테고리이고 `.recognized` 일 때만 담고, 아니면 init 이 nil 로 둔다.
  public let gifticon: GifticonInfo?
  /// 추출 값의 언어 모델 보강 상태. `gifticon` 이 nil 이면 init 이 `.pending(failures: 0)` 으로 둔다.
  /// 두 값이 다 있어도 `.done` 으로 바꾸지 않는다: 저장소는 값이 규칙에서 왔는지 모델에서 왔는지 모르므로,
  /// 다른 보강 버전의 모델 값이 남은 행이 마친 것으로 읽히지 않게 한다. 규칙만으로 두 값을 찾았으면 쓰는 쪽이 `.done` 을 넘긴다.
  public let gifticonModelFill: GifticonModelFill

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
    categories: Set<ImageCategory>,
    gifticon: GifticonInfo? = nil,
    gifticonModelFill: GifticonModelFill = .pending(failures: 0)
  ) {
    self.asset = asset
    self.labels = labels
    self.textRecognition = textRecognition
    self.categories = categories
    // 정규화를 여기 한 곳에 두어 Impl·Fake·읽기 경로가 같은 불변식을 갖는다.
    self.gifticon = if categories.contains(.gifticon), case .recognized = textRecognition {
      gifticon
    } else {
      nil
    }
    self.gifticonModelFill = self.gifticon == nil ? .pending(failures: 0) : gifticonModelFill
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

/// 기프티콘 추출 값의 언어 모델 보강 상태 (docs/ARCHITECTURE.md §4 저장소).
public enum GifticonModelFill: Sendable, Hashable {
  /// 지금 값은 규칙 추출 값이고 보강하지 않았다. 모델을 쓸 수 있으면 소급 보강 대상이다.
  /// `failures` 는 지금 보강 버전으로 시도해 실패한 횟수.
  case pending(failures: Int)
  /// 다른 보강 버전(`GifticonExtractor.modelFillVersion`)으로 보강했다. 값에 옛 확인 규칙으로 받은 모델 값이 남아 있을 수 있어,
  /// 모델을 쓸 수 있든 없든 소급이 규칙 추출부터 다시 계산한 값으로 되돌린다.
  case stale
  /// 지금 보강 버전으로 마쳤다(채웠거나, 확인된 값이 없었거나, 채울 필드가 없었거나, 실패 한도에 닿았다).
  case done

  /// 이 횟수만큼 실패하면 보강을 마친 것으로 둔다(임시 값).
  public static let maximumFailures = 3

  /// 규칙 추출만 한 값의 보강 상태: 두 값을 찾았으면 `.done`, 아니면 `.pending(failures: 0)`.
  /// 쓸 때만 쓴다(읽기 정규화가 아니다, `IndexedImage.gifticonModelFill`).
  public static func initial(for gifticon: GifticonInfo?) -> GifticonModelFill {
    if let gifticon, gifticon.expiryDate != nil, gifticon.redemptionPlace != nil {
      .done
    } else {
      .pending(failures: 0)
    }
  }
}

/// 소급 보강 한 장의 결과(`PhotoStoreClient.saveGifticonModelFills`). 어느 경우든 인덱서가 저장된 줄로 규칙 추출부터
/// 다시 계산한 값을 담아, 다른 보강 버전의 모델 값이 남지 않게 한다.
public enum GifticonModelFillResult: Sendable, Hashable {
  /// 규칙 값 + 확인한 모델 값(또는 채울 필드가 없어 규칙 값만). 추출 값을 이것으로 바꾸고 보강을 마친 것으로 둔다.
  case filled(GifticonInfo)
  /// 모델이 이 이미지에서 실패했다. 추출 값을 규칙 값으로 바꾸고 실패 수를 하나 늘린다(`.stale` 이면 0 에서).
  /// 한도(`GifticonModelFill.maximumFailures`)에 닿으면 마친 것으로 둔다.
  case failed(rules: GifticonInfo)
  /// 모델을 지금 쓸 수 없거나 시스템이 요청을 받지 않았다(입력과 무관). 추출 값을 규칙 값으로 바꾸고 보강하지 않은 상태로 둔다. 실패 수는 그대로다(`.stale` 이면 0).
  /// `.stale` 행을 되돌릴 때 쓴다(`.pending` 행은 이미 규칙 값이라 쓸 것이 없다).
  case deferred(rules: GifticonInfo)
}
