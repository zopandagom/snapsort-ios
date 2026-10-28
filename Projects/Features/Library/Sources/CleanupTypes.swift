import Core

/// 보관함의 "정리 도우미" 카드가 여는 화면 (docs/ARCHITECTURE.md §4 정리 도우미).
/// 캡처 인박스는 정리 화면의 줄로 연다.
enum CleanupRoute: Hashable {
  case cleanup
  case captureInbox
}

/// 정리 화면 내용.
public enum CleanupContent: Equatable, Sendable {
  case loading
  /// 이번 방문에 지운 이미지를 뺀 후보. 후보가 없으면 섹션이 비어 있다.
  case loaded(CleanupSections)
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 목록이 있을 때 실패하면 지난 목록을 둔다.
  case failed
}

/// 캡처 인박스 내용.
public enum CaptureInboxContent: Equatable, Sendable {
  case loading
  /// 이번 방문에 보관했거나 지운 이미지를 뺀 대상, 최신순. 비어 있으면 대상이 없다.
  case loaded([ImageAsset])
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 목록이 있을 때 실패하면 지난 목록을 둔다.
  case failed
}

/// 삭제 결과 안내. 지운 수가 0 이면 건너뜀만 알린다.
public struct CleanupNotice: Equatable, Sendable {
  public let deletedCount: Int
  public let skippedCount: Int

  public init(deletedCount: Int, skippedCount: Int) {
    self.deletedCount = deletedCount
    self.skippedCount = skippedCount
  }
}

/// 알림 창으로 알리는 실패. 사용자가 시스템 확인 창에서 취소한 것은 실패가 아니라 알리지 않는다.
public enum CleanupAlert: Equatable, Sendable {
  /// 사진을 지울 권한이 없다.
  case deleteNotAuthorized
  /// 그 밖의 이유로 지우지 못했다.
  case deleteFailed
  /// 캡처 인박스에서 보관을 저장하지 못했다.
  case keepFailed
}
