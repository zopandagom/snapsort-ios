import Core
import PhotoLibraryInterface
import Photos
import Synchronization

/// 이미지가 추가·삭제된 변경만 골라 무엇이 바뀌었는지 스트림으로 알린다.
/// 영상만 바뀐 경우나 즐겨찾기·편집 같은 내용 변경은 보내지 않는다.
/// PhotoKit 은 백그라운드 큐에서 콜백을 부르므로 조회 결과를 Mutex 로 보호한다.
final class ImageChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
  private let fetchResult: Mutex<PHFetchResult<PHAsset>>
  private let continuation: AsyncStream<ImageChange>.Continuation

  /// 비교 기준 조회. 메인 스레드 밖에서 만든다.
  init(continuation: AsyncStream<ImageChange>.Continuation) {
    self.fetchResult = Mutex(PHAsset.fetchAssets(with: .image, options: nil))
    self.continuation = continuation
  }

  func photoLibraryDidChange(_ changeInstance: PHChange) {
    let change = self.fetchResult.withLock { fetchResult -> ImageChange? in
      guard let details = changeInstance.changeDetails(for: fetchResult) else { return nil }
      fetchResult = details.fetchResultAfterChanges
      // 증분 정보가 없으면 무엇이 바뀌었는지 알 수 없으므로, 추가된 이미지를 변환하지 않고 전체 다시 조회를 알린다.
      guard details.hasIncrementalChanges else { return .reloadAll }
      return Self.imageChange(
        inserted: details.insertedObjects.map(PhotoLibraryClientImpl.imageAsset(from:)),
        removed: details.removedObjects.map(\.localIdentifier)
      )
    }
    if let change {
      self.continuation.yield(change)
    }
  }

  /// 추가·삭제가 있을 때만 그 차이를 알린다. 즐겨찾기·편집 같은 내용 변경만 있으면 nil.
  static func imageChange(inserted: [ImageAsset], removed: [ImageAsset.ID]) -> ImageChange? {
    guard !inserted.isEmpty || !removed.isEmpty else { return nil }
    return .incremental(inserted: inserted, removed: removed)
  }
}
