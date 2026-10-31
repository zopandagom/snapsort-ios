import Core

/// 이미지 분석 (Vision 이미지 분류·OCR·바코드·특징 벡터).
/// 구현은 ImageAnalysisImpl, 테스트 대역은 ImageAnalysisTesting 에 있다.
public protocol ImageAnalysisClient: Sendable {
  /// 썸네일에서 이미지 분류 라벨을 신뢰도 높은 순으로 돌려준다. `minimumConfidence` 보다 낮은 라벨은 뺀다.
  /// 분류는 `ClassificationRules.minimumLabelConfidence` 를, 기준 조정용 기록은 더 낮은 값을 넘긴다.
  /// 라벨을 카테고리로 바꾸는 것은 받는 쪽(규칙 분류기)이 한다.
  /// 앱이 뒤에 있으면 앞에서 불러 둔 요청으로만 분류한다(`isClassificationAvailable`).
  /// 요청이 시한(Impl `VisionSession.timeout`, 세대의 첫 요청은 `firstUseTimeout`)을 넘기면 `.failed` 다.
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
  /// 인덱서 1단계(`IndexingRun.classify`)도 OCR 대상 판정에 썸네일로 부르고 바코드가 있는지만 쓴다(내용은 버린다).
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func detectBarcodes(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [DetectedBarcode]

  /// 비슷한 사진 비교용 특징 벡터를 이 기기에서 만들 수 있는지. 시뮬레이터는 false 다(Vision 이 실패하거나 멈추거나
  /// 모든 사진에 같은 벡터를 준다, docs/ARCHITECTURE.md §4 정리 도우미 실측). false 면 부르는 쪽이 계산·대기 조회를 하지 않는다.
  /// 지금 만들 수 있는지다. 앱이 앞에 있는 동안 요청이 시한(Impl `VisionSession.timeout`, 세대의 첫 요청은 `firstUseTimeout`)을 넘기면
  /// 이 프로세스가 끝날 때까지 false 가 된다. 뒤에 있는 동안(또는 요청 도중 뒤로 간 적이 있는 요청이) 넘기면 이 프로세스에서 앱이 뒤에 있을 때만
  /// false 다. 세션이 없고(버려졌고) 분류·벡터 작업이 시한을 넘기고 돌아오지 않은 것이 이 프로세스에 둘 이상이면 그동안 앞에서도 false 다(`isClassificationAvailable` 과
  /// 같다).
  /// 앱이 뒤에 있으면 앞에서 벡터에 성공한 요청을 이 프로세스가 쥐고 있을 때만 true 다(분류와 같은 이유, `isClassificationAvailable`).
  /// 부르는 쪽은 부를 때마다 묻는다.
  var isFeaturePrintAvailable: Bool { get }

  /// 지금 이미지 분류를 할 수 있는지. 앱이 앞에 있으면 대개 true 다(요청할 때 분류 모델을 불러 둔다). 이 프로세스에서 분류·벡터 작업이
  /// 시한을 넘기고 돌아오지 않은 것이 둘 이상이고 세션이 없으면(버려졌으면) 그것이 돌아올 때까지(대개 앱을 다시 시작할 때까지) 앞에서도 false 다.
  /// 뒤에 있으면 이 프로세스가 앞에서 분류에 성공한 요청을 쥐고 있을 때만 true 다(뒤에서는 모델을 새로 불러오지 못할 수 있어 새로 불러 보지 않는다,
  /// docs/ARCHITECTURE.md §4 인덱싱). false 일 때 `classify` 는 Vision 을 부르지 않고 `.failed` 를 던진다. 부르는 쪽은 부를 때마다 묻는다.
  var isClassificationAvailable: Bool { get }

  /// 썸네일(`ImageSize.thumbnail`, 대체 버전이 아닌 것)에서 `ImageFeaturePrint.version` 의 요청으로 특징 벡터를 만든다.
  /// 앱이 뒤에 있으면 앞에서 불러 둔 요청으로만 만든다(`isFeaturePrintAvailable`, docs/ARCHITECTURE.md §4 정리 도우미).
  /// 쓸 수 없는 기기에서는 Vision 을 부르지 않고 `.failed` 를 던진다. 요청이 시한을 넘겨도 `.failed` 다.
  /// 호출한 Task 가 취소되면 `.cancelled` 를 던진다.
  func featurePrint(_ image: AnalysisImage) async throws(ImageAnalysisError) -> ImageFeaturePrint

  /// 앱이 앞에 있는지 알린다. 특징 벡터의 시한 차단을 앞·뒤로 나누고 뒤에서 분류·벡터를 앞에서 불러 둔 요청으로만 하는 데 쓴다. 처음 값은 true 다.
  /// 부르는 곳은 Indexing 실행기 하나이고 값이 바뀔 때만 부른다. 프로세스에 하나라 같은 프로세스의 모든 구현 값이 같이 본다(Impl).
  /// 구현은 자기 잠금만 쥐고 다른 Client 를 부르지 않는다(실행기가 자기 잠금 안에서 부른다).
  func appActivityChanged(isActive: Bool)
}
