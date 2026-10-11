/// 분류 파이프라인 ③단계(OCR)에 넘길 이미지를 고른다 (docs/ARCHITECTURE.md §4).
/// OCR 은 기기에 있는 가장 큰 버전을 읽어야 해서 비싸므로, 메타데이터(①)와 이미지 분류 라벨(②)만 보고 미리 거른다.
public enum TextRecognitionPolicy {
  /// 다음 중 하나면 OCR 한다.
  /// - 기기에서 찍은 스크린샷
  /// - 정보형 카테고리 라벨이나 글자가 많은 라벨(예: "document", "receipt", "ticket")이 있다
  /// - 위치가 없고 사진형 라벨(음식·인물·반려동물·풍경)도 없다. 앨범에 저장한 기프티콘·쿠폰처럼 촬영하지 않은 이미지를 잡는다
  public static func needsTextRecognition(asset: ImageAsset, labels: [ImageLabel]) -> Bool {
    if asset.isScreenshot {
      return true
    }
    let identifiers = Set(labels.map(\.identifier))
    if !identifiers.isDisjoint(with: ClassificationRules.textLabels) {
      return true
    }
    return asset.coordinate == nil && identifiers.isDisjoint(with: ClassificationRules.allPhotoLabels)
  }
}
