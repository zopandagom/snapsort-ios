import Core

/// 이미지 분석 (Vision 이미지 분류·OCR·바코드·특징 벡터).
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

  /// 비슷한 사진 비교용 특징 벡터를 이 기기에서 만들 수 있는지. 시뮬레이터는 false 다(Vision 이 실패하거나 멈추거나
  /// 모든 사진에 같은 벡터를 준다, docs/ARCHITECTURE.md §4 정리 도우미 실측). false 면 부르는 쪽이 계산·대기 조회를 하지 않는다.
  /// 요청이 시한(Impl `FeaturePrinting.timeout`)을 넘기면 이 프로세스가 끝날 때까지 false 가 된다. 부르는 쪽은 부를 때마다 묻는다.
  var isFeaturePrintAvailable: Bool { get }

  /// 썸네일(`ImageSize.thumbnail`, 대체 버전이 아닌 것)에서 `ImageFeaturePrint.version` 의 요청으로 특징 벡터를 만든다.
  /// 쓸 수 없는 기기에서는 Vision 을 부르지 않고 `.failed` 를 던진다. 요청이 시한을 넘겨도 `.failed` 다.
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func featurePrint(_ image: AnalysisImage) async throws(ImageAnalysisError) -> ImageFeaturePrint
}
