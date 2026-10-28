/// 분류 파이프라인 ③단계(OCR)에 넘길 이미지를 고른다 (docs/ARCHITECTURE.md §4).
/// OCR 은 기기에 있는 가장 큰 버전을 읽어야 해서 비싸므로, 메타데이터(①)와 이미지 분류 라벨(②)만 보고 미리 거르고,
/// 그것으로 대상이 아닌 위치 없는 이미지는 같은 썸네일의 바코드로 한 번 더 본다.
public enum TextRecognitionPolicy {
  /// 다음 중 하나면 OCR 한다.
  /// - 기기에서 찍은 스크린샷이거나 `screenshot` 라벨이 있다(남이 보낸 캡처·저장한 기프티콘)
  /// - 정보형 카테고리 라벨이나 글자가 많은 라벨(예: "document", "receipt", "ticket")이 `textLabelMinimumConfidence` 이상이다
  ///
  /// 위치나 사진형 카테고리는 보지 않는다. 실기기 보관함 1만 장에서 위치도 사진형 카테고리도 없어서 OCR 한 이미지는
  /// 모두 기타였고(저장한 기프티콘은 대부분 글자 라벨로 잡혔다), OCR 대상의 약 30% 였다.
  /// 라벨·메타데이터만 본 판정이다. 저장한 기프티콘 중에는 음식 라벨이 강하고 글자 라벨이 기준에 못 미치는 것이 있어(사용자 기기 샘플)
  /// 운영 판정(인덱서·기록 도구)은 바코드 확인(`needsBarcodeCheck`)까지 본 `needsTextRecognition(asset:labels:hasBarcode:)` 를 쓴다.
  public static func needsTextRecognition(asset: ImageAsset, labels: [ImageLabel]) -> Bool {
    if asset.isScreenshot || labels.contains(where: { $0.identifier == ClassificationRules.screenshotLabel }) {
      return true
    }
    return labels.contains {
      ClassificationRules.textLabels.contains($0.identifier)
        && $0.confidence >= ClassificationRules.textLabelMinimumConfidence
    }
  }

  /// 바코드 인식으로 한 번 더 볼 이미지: 위 판정으로는 OCR 대상이 아니고 위치가 없다.
  /// 저장한 기프티콘은 위치가 없고 바코드가 있지만, 라벨이 음식·문서 쪽으로 약하게만 붙어 위 판정을 아슬아슬하게 넘거나 못 넘는다.
  /// 위치 있는 사진(카메라 촬영)은 보지 않는다: 바코드가 찍혀도 기프티콘이 아니고, 대부분의 사진에 인식 비용이 들기 때문이다.
  /// 바코드는 대상 판정에만 쓰고 카테고리 신호로 쓰지 않는다(상품 포장·탑승권·영수증에도 있다).
  public static func needsBarcodeCheck(asset: ImageAsset, labels: [ImageLabel]) -> Bool {
    asset.coordinate == nil && !self.needsTextRecognition(asset: asset, labels: labels)
  }

  /// 바코드 인식 결과까지 본 OCR 대상. `hasBarcode` 는 `needsBarcodeCheck` 가 true 일 때 썸네일에서 글자로 읽을 수 있는 바코드를 찾았는지다.
  /// `needsBarcodeCheck` 가 false 면 `hasBarcode` 는 보지 않는다(위치 있는 사진에 true 를 넘겨도 대상이 되지 않는다).
  public static func needsTextRecognition(asset: ImageAsset, labels: [ImageLabel], hasBarcode: Bool) -> Bool {
    self.needsTextRecognition(asset: asset, labels: labels)
      || (hasBarcode && self.needsBarcodeCheck(asset: asset, labels: labels))
  }
}
