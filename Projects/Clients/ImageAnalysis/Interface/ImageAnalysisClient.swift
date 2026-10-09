import Core

/// 이미지 분석 (Vision 이미지 분류·OCR).
/// 구현은 ImageAnalysisImpl, 테스트 대역은 ImageAnalysisTesting 에 있다.
public protocol ImageAnalysisClient: Sendable {
  /// 썸네일에서 이미지 분류 라벨을 신뢰도 높은 순으로 돌려준다. 신뢰도가 낮은 라벨은 뺀다.
  /// 라벨을 카테고리로 바꾸는 것은 받는 쪽(규칙 분류기)이 한다.
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func classify(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [ImageLabel]

  /// 이미지에서 한국어·영어 텍스트를 줄 단위로 읽어 읽는 순서대로 돌려준다. 글자가 없는 줄은 뺀다.
  /// 작은 글자를 놓치지 않도록 기기에 있는 가장 큰 버전(`ImageSize.largestAvailable`)을 넘긴다.
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine]
}
