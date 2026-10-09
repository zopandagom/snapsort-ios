import Core

/// 사진 보관함 접근.
/// 구현은 PhotoLibraryImpl, 테스트 대역은 PhotoLibraryTesting 에 있다.
public protocol PhotoLibraryClient: Sendable {
  /// 권한 팝업 없이 현재 상태를 읽는다.
  func accessState() -> PhotoAccessState

  /// 권한 팝업을 띄우고 사용자의 선택 결과를 돌려준다.
  func requestAccess() async -> PhotoAccessState

  /// 최신순 이미지(영상 제외)와 메타데이터. 픽셀은 읽지 않는다.
  func fetchImageAssets() async -> [ImageAsset]

  /// 분석에 쓸 이미지를 읽는다. iCloud 원본은 내려받지 않고 기기에 있는 버전만 쓴다 (docs/ARCHITECTURE.md §4).
  /// 호출한 Task 가 취소되면 읽기 요청도 취소하고 `.cancelled` 를 던진다.
  func loadImage(id: ImageAsset.ID, size: ImageSize) async throws(ImageLoadError) -> AnalysisImage

  /// 제한 접근(`.limited`)일 때 허용할 사진을 더 고르는 시스템 화면을 띄우고, 닫힐 때까지 기다린다.
  /// 고른 결과는 돌려주지 않는다. 고른 사진이 바뀌면 `imageChanges()` 가 알린다.
  @MainActor
  func presentLimitedLibraryPicker() async

  /// 이미지가 추가·삭제될 때마다 무엇이 바뀌었는지 보낸다 (촬영·삭제, 제한 접근 선택 목록 변경 등). 즐겨찾기·편집 같은 내용 변경은 보내지 않는다.
  /// 받는 쪽은 차이만 반영하고, `.reloadAll` 일 때만 `fetchImageAssets()` 로 전체를 다시 조회한다.
  /// 돌려받은 시점부터 관찰하므로, 처음 조회 전에 받아 두면 그 사이 변경도 놓치지 않는다.
  /// 대신 처음 조회 결과와 겹치는 변경이 올 수 있으므로 받는 쪽은 같은 변경을 두 번 반영해도 결과가 같게 만든다 (식별자 집합 등).
  /// 변경은 버리지 않고 순서대로 쌓이며, 구독한 Task 가 취소되면 관찰도 끝난다.
  func imageChanges() async -> AsyncStream<ImageChange>
}
