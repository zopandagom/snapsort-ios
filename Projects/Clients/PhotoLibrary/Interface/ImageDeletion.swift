import Core

/// `deleteImages(ids:)` 결과. 두 집합은 겹치지 않고 합하면 요청한 식별자다.
public struct ImageDeletionResult: Sendable, Equatable {
  /// 지운 이미지. '최근 삭제된 항목'으로 간다.
  public let deletedIDs: Set<ImageAsset.ID>
  /// 부를 때 보관함에서 찾지 못해 건너뛴 이미지(이미 지워짐, 제한 접근 선택 밖).
  public let skippedIDs: Set<ImageAsset.ID>

  public init(deletedIDs: Set<ImageAsset.ID>, skippedIDs: Set<ImageAsset.ID>) {
    self.deletedIDs = deletedIDs
    self.skippedIDs = skippedIDs
  }
}

/// 지우지 못한 이유. 어느 경우든 아무것도 지우지 않았다고 본다(일부만 지워졌는지는 확인하지 못했다, 보관함 변경 알림이 맞춘다).
public enum ImageDeletionError: Error, Equatable {
  /// 사용자가 시스템 확인 창에서 취소했다.
  case userCancelled
  /// 사진 읽기·쓰기 권한이 없다(거부·미정·제한됨).
  case notAuthorized
  /// 그 밖의 실패.
  case failed
}
