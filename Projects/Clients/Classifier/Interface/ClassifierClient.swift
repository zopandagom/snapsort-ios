import Core

/// 온디바이스 언어 모델(Foundation Models)로 OCR 텍스트를 해석한다 (docs/ARCHITECTURE.md §4).
/// 답은 확인 전이다. 받는 쪽이 Core(`ModelCategoryPolicy`, `GifticonExtractor.filling`)로 원문과 대조해 쓴다.
/// 구현은 ClassifierImpl, 테스트 대역은 ClassifierTesting 에 있다.
public protocol ClassifierClient: Sendable {
  /// 지금 모델을 쓸 수 있는지(`SystemLanguageModel.default.availability == .available`).
  /// 기기 지원·Apple Intelligence 설정·모델 다운로드에 따라 실행 도중 바뀌므로 쓸 때마다 묻는다.
  /// 참이어도 요청이 실패할 수 있다(시뮬레이터).
  func isModelAvailable() -> Bool

  /// 글자를 읽었는데 규칙 분류가 기타뿐인 이미지의 OCR 줄을 보고 정보형 카테고리를 제안한다. 없으면 빈 집합.
  /// 정보형 밖의 카테고리는 돌려주지 않는다. 먼저 호출한 Task 가 취소됐으면 `.cancelled`,
  /// 모델을 쓸 수 없으면(`isModelAvailable()` 거짓) `.unavailable` 을 던지고, 그다음 줄이 없으면 모델을 부르지 않고 빈 집합이다.
  /// 응답 도중이나 뒤에 Task 가 취소되면 `.cancelled`, 응답이 실패했고 그때 모델을 쓸 수 없으면 `.unavailable`,
  /// 그 밖의 실패는 `.failed` 다.
  func classify(_ textLines: [RecognizedTextLine]) async throws(ClassifierError) -> Set<ImageCategory>

  /// 기프티콘 이미지의 OCR 줄에서 만료일·교환처를 적힌 그대로 찾는다. 없으면 그 필드가 nil.
  /// 먼저 호출한 Task 가 취소됐으면 `.cancelled`, 모델을 쓸 수 없으면 `.unavailable` 을 던진다. 줄이 없어도 모델을 부른다.
  /// 응답 도중이나 뒤의 취소, 응답 실패 때의 쓸 수 없음·그 밖의 실패는 `classify` 와 같다.
  func extractGifticon(from textLines: [RecognizedTextLine]) async throws(ClassifierError) -> GifticonModelAnswer
}
