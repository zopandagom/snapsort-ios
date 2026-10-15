/// 분류 파이프라인 ③단계(OCR)에 넘길 이미지를 고른다 (docs/ARCHITECTURE.md §4).
/// OCR 은 기기에 있는 가장 큰 버전을 읽어야 해서 비싸므로, 메타데이터(①)와 이미지 분류 라벨(②)만 보고 미리 거른다.
public enum TextRecognitionPolicy {
  /// 다음 중 하나면 OCR 한다.
  /// - 기기에서 찍은 스크린샷
  /// - 정보형 카테고리 라벨이나 글자가 많은 라벨(예: "document", "receipt", "ticket")이 있다
  /// - 위치가 없고 사진형 카테고리(음식·인물·반려동물·풍경)도 없다. 앨범에 저장한 기프티콘·쿠폰처럼 촬영하지 않은 이미지를 잡는다.
  ///   사진형 판단은 규칙 분류기와 같다(카테고리별 신뢰도 기준, 그림 제외). 기타로 분류될 이미지를 OCR 없이 남기지 않기 위해서다.
  ///
  /// 한계: 상품 사진이 든 저장 기프티콘에 `coupon`·`gift_card` 없이 음식 라벨만 붙으면 OCR 하지 않는다.
  /// 실기기 보관함에서 정답을 확인한 86장(그중 62장을 정확도 픽스처에 둠) 중 1장, 상품 사진이 든 백화점 상품권이 그렇다.
  /// 위치 없이 음식만 붙은 이미지를 OCR 대상에 넣으면 1만 장 중 약 570장이 늘어, OCR 대상 조정 작업에서 비용과 함께 정한다.
  public static func needsTextRecognition(asset: ImageAsset, labels: [ImageLabel]) -> Bool {
    if asset.isScreenshot {
      return true
    }
    let identifiers = Set(labels.map(\.identifier))
    if !identifiers.isDisjoint(with: ClassificationRules.textLabels) {
      return true
    }
    return asset.coordinate == nil && RuleClassifier.photoCategories(labels: labels).isEmpty
  }
}
