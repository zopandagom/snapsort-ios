import Core

/// 이미지 분석 (Vision 이미지 분류·OCR·바코드).
/// 구현은 ImageAnalysisImpl, 테스트 대역은 ImageAnalysisTesting 에 있다.
public protocol ImageAnalysisClient: Sendable {
  /// 썸네일에서 이미지 분류 라벨을 신뢰도 높은 순으로 돌려준다. `minimumConfidence` 보다 낮은 라벨은 뺀다.
  /// 분류는 `ClassificationRules.minimumLabelConfidence` 를, 기준 조정용 기록은 더 낮은 값을 넘긴다.
  /// 라벨을 카테고리로 바꾸는 것은 받는 쪽(규칙 분류기)이 한다.
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func classify(_ image: AnalysisImage, minimumConfidence: Float) async throws(ImageAnalysisError) -> [ImageLabel]

  /// 이미지에서 한국어·영어 텍스트를 줄 단위로 읽어 읽는 순서대로 돌려준다. 글자가 없는 줄은 뺀다.
  /// 작은 글자를 놓치지 않도록 기기에 있는 가장 큰 버전(`ImageSize.largestAvailable`)을 넘긴다
  /// (Debug 기록 도구의 OCR 해상도 비교는 그 이미지를 줄인 입력도 넘긴다).
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine]

  /// 이미지에서 글자로 읽을 수 있는 바코드를 큰 것부터 돌려준다. 바코드가 없으면 빈 배열이다.
  /// 기프티콘 바코드를 크게 보이려고(다시 그리거나 영역을 확대) 사용자가 기프티콘 목록·정리 화면에서 연 상세에서 부른다(결과는 저장하지 않는다).
  /// OCR 과 같이 기기에 있는 가장 큰 버전(`ImageSize.largestAvailable`)을 넘긴다.
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func detectBarcodes(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [DetectedBarcode]
}
