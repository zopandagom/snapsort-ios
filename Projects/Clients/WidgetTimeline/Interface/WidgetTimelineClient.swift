/// 위젯 타임라인 갱신 요청 (docs/ARCHITECTURE.md §4 만료 임박 위젯).
/// 구현은 WidgetTimelineImpl, 테스트 대역은 WidgetTimelineTesting 에 있다.
public protocol WidgetTimelineClient: Sendable {
  /// 만료 임박 위젯이 저장소를 다시 읽게 요청한다. 실제로 언제 다시 읽을지는 시스템이 정하고, 결과를 돌려주지 않는다.
  /// 앱이 앞에 있을 때 한 요청은 갱신 예산을 덜 쓴다고 보지만 확인 못 한 값이라, 화면 흐름에서는 위젯에 보일 값이 바뀔 때만 부른다.
  /// App init 의 실행마다 1회 요청은 예외다(저장소를 옮기거나 이전한 뒤 위젯을 회복시킨다, docs/ARCHITECTURE.md §4 만료 임박 위젯).
  /// BG 작업이 저장소에 썼을 때(여행 교체 제외) 완료 전 1회 요청도 예외다(BackgroundIndexing Impl. 값 비교는 보관함 화면에서 하므로 BG 에서는 하지 않는다).
  func reloadExpiryWidget()
}
