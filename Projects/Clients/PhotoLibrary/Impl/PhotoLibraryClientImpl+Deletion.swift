import Core
import Foundation
import PhotoLibraryInterface
import Photos

// 삭제 (docs/ARCHITECTURE.md §4 정리 도우미). 확인 창은 시스템이 띄운다.
extension PhotoLibraryClientImpl {
  /// 식별자 조회가 메인 스레드를 막지 않도록 메인 밖에서 실행한다.
  /// 취소를 확인하지 않는다: 확인 창은 Task 취소로 닫히지 않고, 그 결과를 버리면 지운 사진을 모른 채 남는다.
  @concurrent
  public func deleteImages(ids: Set<ImageAsset.ID>) async throws(ImageDeletionError) -> ImageDeletionResult {
    guard Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead else {
      throw .notAuthorized
    }
    guard !ids.isEmpty else {
      return ImageDeletionResult(deletedIDs: [], skippedIDs: [])
    }
    let found = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
    var foundIDs: [ImageAsset.ID] = []
    found.enumerateObjects { asset, _, _ in
      foundIDs.append(asset.localIdentifier)
    }
    let plan = Self.deletionPlan(requested: ids, found: foundIDs)
    guard !plan.toDelete.isEmpty else {
      return ImageDeletionResult(deletedIDs: [], skippedIDs: plan.skipped)
    }
    // PHFetchResult 는 Sendable 이 아니라 변경 블록 안에서 다시 찾는다. 그 사이 사라진 사진은 PhotoKit 이 뺀다.
    let toDelete = Array(plan.toDelete)
    do {
      try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: toDelete, options: nil))
      }
    } catch {
      throw Self.deletionError(from: error)
    }
    return ImageDeletionResult(deletedIDs: plan.toDelete, skippedIDs: plan.skipped)
  }

  /// 요청한 것 중 찾은 것은 지울 것, 못 찾은 것은 건너뛸 것이다. 요청에 없는 식별자는 무시한다.
  static func deletionPlan(
    requested: Set<ImageAsset.ID>,
    found: [ImageAsset.ID]
  ) -> (toDelete: Set<ImageAsset.ID>, skipped: Set<ImageAsset.ID>) {
    let toDelete = requested.intersection(found)
    return (toDelete, requested.subtracting(toDelete))
  }

  /// 사용자 취소(3072)와 권한 오류(3310·3311)만 가른다. 다른 도메인(`CancellationError` 포함)은 `.failed` 다.
  static func deletionError(from error: any Error) -> ImageDeletionError {
    let nsError = error as NSError
    guard nsError.domain == PHPhotosErrorDomain else { return .failed }
    switch nsError.code {
    case PHPhotosError.userCancelled.rawValue: return .userCancelled
    case PHPhotosError.accessRestricted.rawValue, PHPhotosError.accessUserDenied.rawValue: return .notAuthorized
    default: return .failed
    }
  }
}
