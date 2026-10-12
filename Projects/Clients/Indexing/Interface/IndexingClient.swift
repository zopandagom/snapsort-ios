/// 보관함 이미지를 분류 파이프라인으로 분석해 저장소에 맞춰 두는 인덱서 (docs/ARCHITECTURE.md §4).
/// 다른 Client(PhotoLibrary·ImageAnalysis·PhotoStore)를 조합한다.
/// 구현은 IndexingImpl, 테스트 대역은 IndexingTesting 에 있다.
public protocol IndexingClient: Sendable {
  /// 인덱싱을 시작하고 진행률을 보낸다. 보관함과 저장소를 비교해 새 이미지만 분석하고, 보관함에서 지워진 이미지의 결과는 지운다.
  /// 비교 기준은 지금 읽을 수 있는 이미지이므로, 제한 접근(`.limited`)이면 고르지 않은 이미지의 결과도 지운다.
  /// 화면 안내("선택한 사진만 분류합니다")와 같게 고른 사진만 분류하고, 다시 전체 접근을 주면 처음부터 분석한다.
  /// 처음 비교를 마친 뒤에도 보관함 변경을 계속 반영하므로, 받는 쪽이 구독을 끝내야(Task 취소) 멈춘다.
  /// 받는 쪽이 늦게 읽으면 지난 진행률은 버리고 가장 최근 값만 남긴다.
  /// 사진을 읽을 권한이 없으면(`PhotoAccessState.canRead` 거짓) 저장 결과를 그대로 두고 스트림을 끝낸다.
  /// 저장소를 읽거나 쓰지 못하면 멈추고 스트림을 끝낸다. 다음 `run()` 에서 저장된 데까지 건너뛰고 이어서 분석한다.
  func run() -> AsyncStream<IndexingProgress>
}
