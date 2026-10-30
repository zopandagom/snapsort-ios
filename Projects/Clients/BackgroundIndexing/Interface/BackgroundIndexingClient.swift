/// 앱이 뒤에 있거나 닫혀 있을 때의 분류 (docs/ARCHITECTURE.md §4 인덱싱). 다른 Client(Indexing·TripPlace·WidgetTimeline)를 조합한다.
/// 앱이 뒤로 가면 진행 중 저장이 끝날 때까지 실행 시간을 빌려 앞 실행을 멈추고 BG 처리 요청(충전 중)을 제출한다.
/// 시스템이 그 요청을 실행하면 분류를 이어 하고 1단계를 마친 뒤 여행 장소 이름 미리 받기 회차를 한 번 돌린다.
/// 구현은 BackgroundIndexingImpl, 테스트 대역은 BackgroundIndexingTesting 에 있다.
public protocol BackgroundIndexingClient: Sendable {
  /// 앱이 뒤로 갔다(scenePhase `.background`, 화면이 처음 생길 때의 값 포함). 진행 중 저장이 끝날 때까지 실행 시간을 빌려 분류와
  /// 미리 받기의 저장소 출입을 멈추고, 인덱서가 있으면 BG 처리 요청을 제출한다. 이미 뒤에 있으면 아무것도 하지 않는다.
  @MainActor func appDidEnterBackground()
  /// 앱이 앞으로 왔다(scenePhase `.active`, 화면이 처음 생길 때의 값 포함). 멈춘 분류와 미리 받기 저장소 출입을 다시 연다.
  /// 이미 앞에 있으면 아무것도 하지 않는다.
  @MainActor func appDidBecomeActive()
}
