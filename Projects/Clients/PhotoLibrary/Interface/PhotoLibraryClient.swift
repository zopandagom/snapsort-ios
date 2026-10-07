/// 사진 보관함 접근.
/// 구현은 PhotoLibraryImpl, 테스트 대역은 PhotoLibraryTesting 에 있다.
public protocol PhotoLibraryClient: Sendable {
  /// 권한 팝업 없이 현재 상태를 읽는다.
  func accessState() -> PhotoAccessState

  /// 권한 팝업을 띄우고 사용자의 선택 결과를 돌려준다.
  func requestAccess() async -> PhotoAccessState

  /// 최신순 스크린샷 식별자. PHAsset 은 Sendable 이 아니므로 식별자만 넘긴다.
  func fetchScreenshotIdentifiers() async -> [String]
}
