/// 분류 파이프라인 ③단계(OCR)에 넘길 이미지를 고른다 (docs/ARCHITECTURE.md §4).
/// OCR 은 기기에 있는 가장 큰 버전을 읽어야 해서 비싸므로, 메타데이터(①)와 이미지 분류 라벨(②)만 보고 미리 거른다.
public enum TextRecognitionPolicy {
  /// 다음 중 하나면 OCR 한다.
  /// - 기기에서 찍은 스크린샷이거나 `screenshot` 라벨이 있다(남이 보낸 캡처·저장한 기프티콘)
  /// - 정보형 카테고리 라벨이나 글자가 많은 라벨(예: "document", "receipt", "ticket")이 `textLabelMinimumConfidence` 이상이다
  ///
  /// 위치나 사진형 카테고리는 보지 않는다. 실기기 보관함 1만 장에서 위치도 사진형 카테고리도 없어서 OCR 한 이미지는
  /// 모두 기타였고(저장한 기프티콘은 글자 라벨로 잡혔다), OCR 대상의 약 30% 였다.
  /// 위치 없이 음식 라벨만 붙은 저장 기프티콘도 보관함에 없어 OCR 하지 않는다.
  public static func needsTextRecognition(asset: ImageAsset, labels: [ImageLabel]) -> Bool {
    if asset.isScreenshot || labels.contains(where: { $0.identifier == ClassificationRules.screenshotLabel }) {
      return true
    }
    return labels.contains {
      ClassificationRules.textLabels.contains($0.identifier)
        && $0.confidence >= ClassificationRules.textLabelMinimumConfidence
    }
  }
}
