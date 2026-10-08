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
  /// 고른 결과는 돌려주지 않는다. 호출한 쪽이 `fetchImageIdentifiers()` 로 다시 조회한다.
  @MainActor
  func presentLimitedLibraryPicker() async
}
