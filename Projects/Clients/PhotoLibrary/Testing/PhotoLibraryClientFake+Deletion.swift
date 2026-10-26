import Core
import PhotoLibraryInterface

// 삭제 (docs/ARCHITECTURE.md §4 정리 도우미).
public extension PhotoLibraryClientFake {
  /// `deleteImages` 에 넘긴 식별자를 부른 순서대로. 실패한 호출도 포함한다.
  var deletionRequests: [Set<ImageAsset.ID>] {
    self.state.withLock { $0.deletionRequests }
  }

  /// 요청을 기록하고 `deletionGate` 를 기다린 뒤, 권한 → 호출 번호별 실패 순으로 확인한다.
  /// 지금 조회 결과에 있는 것만 지우고 나머지는 건너뛴 것으로 돌려준다. 지운 것이 있으면 증분 변경을 한 번 보낸다(실제 보관함과 같다).
  /// Impl 처럼 Task 취소를 확인하지 않는다.
  func deleteImages(ids: Set<ImageAsset.ID>) async throws(ImageDeletionError) -> ImageDeletionResult {
    let index = self.state.withLock { state in
      defer { state.deletionRequests.append(ids) }
      return state.deletionRequests.count
    }
    await self.deletionGate?(ids)
    guard self.accessState().canRead else { throw .notAuthorized }
    if let error = self.deletionErrors[index] {
      throw error
    }
    return self.sendDeletion(of: ids)
  }

  private func sendDeletion(of ids: Set<ImageAsset.ID>) -> ImageDeletionResult {
    var deleted: Set<ImageAsset.ID> = []
    self.send { state in
      deleted = Set(state.imageAssets.map(\.id)).intersection(ids)
      guard !deleted.isEmpty else { return nil }
      state.imageAssets.removeAll { deleted.contains($0.id) }
      return .incremental(inserted: [], removed: deleted.sorted())
    }
    return ImageDeletionResult(deletedIDs: deleted, skippedIDs: ids.subtracting(deleted))
  }
}
