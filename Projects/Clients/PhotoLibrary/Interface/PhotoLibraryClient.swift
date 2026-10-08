/// 사진 보관함 접근.
/// 구현은 PhotoLibraryImpl, 테스트 대역은 PhotoLibraryTesting 에 있다.
public protocol PhotoLibraryClient: Sendable {
  /// 권한 팝업 없이 현재 상태를 읽는다.
  func accessState() -> PhotoAccessState

  /// 권한 팝업을 띄우고 사용자의 선택 결과를 돌려준다.
  func requestAccess() async -> PhotoAccessState

  /// 최신순 이미지 식별자(영상 제외). PHAsset 은 Sendable 이 아니므로 식별자만 넘긴다.
  func fetchImageIdentifiers() async -> [String]

  /// 제한 접근(`.limited`)일 때 허용할 사진을 더 고르는 시스템 화면을 띄우고, 닫힐 때까지 기다린다.
  /// 고른 결과는 돌려주지 않는다. 고른 사진이 바뀌면 `imageChanges()` 가 알린다.
  @MainActor
  func presentLimitedLibraryPicker() async

  /// 이미지가 추가·삭제될 때마다 값을 보낸다 (촬영·삭제, 제한 접근 선택 목록 변경 등). 즐겨찾기·편집 같은 내용 변경은 보내지 않는다.
  /// 무엇이 바뀌었는지는 주지 않으므로 호출한 쪽이 `fetchImageIdentifiers()` 로 다시 조회한다.
  /// 돌려받은 시점부터 관찰하므로, 처음 조회 전에 받아 두면 그 사이 변경도 놓치지 않는다.
  /// 연달아 온 변경은 하나로 합쳐지고, 구독한 Task 가 취소되면 관찰도 끝난다.
  /// 분류 결과를 저장하게 되면 추가·삭제된 식별자를 보내는 증분 방식으로 바꾼다 (전체 다시 조회는 보관함 크기에 비례).
  func imageChanges() async -> AsyncStream<Void>
}
