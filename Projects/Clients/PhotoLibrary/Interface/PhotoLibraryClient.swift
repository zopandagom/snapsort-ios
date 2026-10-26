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

  /// 제목이 `name` 인 사용자 앨범의 이미지(영상 제외)를 앨범 순서로 준다. 픽셀은 읽지 않는다. 같은 제목이 여럿이면 첫 앨범.
  /// 앨범이 없으면 nil. 제한 접근(`.limited`)에서는 사용자 앨범을 읽을 수 없어 nil 일 수 있다. 지금은 Debug 기록 도구만 쓴다.
  func fetchImageAssets(inAlbumNamed name: String) async -> [ImageAsset]?

  /// 분석·화면 표시에 쓸 이미지를 읽는다. iCloud 원본은 내려받지 않고 기기에 있는 버전만 쓴다 (docs/ARCHITECTURE.md §4).
  /// 호출한 Task 가 취소되면 읽기 요청도 취소하고 `.cancelled` 를 던진다.
  func loadImage(id: ImageAsset.ID, size: ImageSize) async throws(ImageLoadError) -> AnalysisImage

  /// 제한 접근(`.limited`)일 때 허용할 사진을 더 고르는 시스템 화면을 띄우고, 닫힐 때까지 기다린다.
  /// 고른 결과는 돌려주지 않는다. 고른 사진이 바뀌면 `imageChanges()` 가 알린다.
  @MainActor
  func presentLimitedLibraryPicker() async

  /// 이미지가 추가·삭제될 때마다 무엇이 바뀌었는지 보낸다 (촬영·삭제, 앱의 `deleteImages` 성공, 제한 접근 선택 목록 변경 등). 즐겨찾기·편집 같은 내용 변경은 보내지 않는다.
  /// 받는 쪽은 차이만 반영하고, `.reloadAll` 일 때만 `fetchImageAssets()` 로 전체를 다시 조회한다.
  /// 돌려받은 시점부터 관찰하므로, 처음 조회 전에 받아 두면 그 사이 변경도 놓치지 않는다.
  /// 대신 처음 조회 결과와 겹치는 변경이 올 수 있으므로 받는 쪽은 같은 변경을 두 번 반영해도 결과가 같게 만든다 (식별자 집합 등).
  /// 변경은 버리지 않고 순서대로 쌓이며, 구독한 Task 가 취소되면 관찰도 끝난다.
  func imageChanges() async -> AsyncStream<ImageChange>

  /// 이미지를 보관함에서 지운다. 지운 이미지는 '최근 삭제된 항목'에 30일 남는다 (docs/ARCHITECTURE.md §4 정리 도우미).
  /// 시스템이 확인 창을 띄우고 사용자가 고를 때까지 기다린다. 호출한 Task 가 취소돼도 시스템 확인 창은 닫히지 않고,
  /// 사용자가 고를 때까지 기다려 그 결과를 돌려준다(iOS 26.5 시뮬레이터 실측). 취소를 던지지 않는다.
  /// 부를 때 식별자로 다시 찾고, 찾지 못한 것(이미 지워짐, 제한 접근 선택 밖)은 건너뛰어 `skippedIDs` 로 돌려준다. 모두 찾지 못하면 확인 창 없이 돌려준다.
  /// 권한이 `.authorized`·`.limited` 가 아니면 찾기 전에 `.notAuthorized` 를 던진다.
  /// 성공하면 보관함 변경 알림(`imageChanges()`)이 삭제를 한 번 보낸다.
  func deleteImages(ids: Set<ImageAsset.ID>) async throws(ImageDeletionError) -> ImageDeletionResult
}
