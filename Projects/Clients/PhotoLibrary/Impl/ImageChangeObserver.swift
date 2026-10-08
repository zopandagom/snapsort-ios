import Photos
import Synchronization

/// 이미지가 추가·삭제된 변경만 골라 스트림으로 알린다.
/// 영상만 바뀐 경우나 즐겨찾기·편집 같은 내용 변경은 보내지 않는다 (받는 쪽이 전체를 다시 조회하므로).
/// PhotoKit 은 백그라운드 큐에서 콜백을 부르므로 조회 결과를 Mutex 로 보호한다.
final class ImageChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
  private let fetchResult: Mutex<PHFetchResult<PHAsset>>
  private let continuation: AsyncStream<Void>.Continuation

  /// 비교 기준 조회. 메인 스레드 밖에서 만든다.
  init(continuation: AsyncStream<Void>.Continuation) {
    self.fetchResult = Mutex(PHAsset.fetchAssets(with: .image, options: nil))
    self.continuation = continuation
  }

  func photoLibraryDidChange(_ changeInstance: PHChange) {
    let imagesAddedOrRemoved = self.fetchResult.withLock { fetchResult in
      guard let details = changeInstance.changeDetails(for: fetchResult) else { return false }
      fetchResult = details.fetchResultAfterChanges
      return Self.shouldNotify(
        hasIncrementalChanges: details.hasIncrementalChanges,
        insertedCount: details.insertedIndexes?.count ?? 0,
        removedCount: details.removedIndexes?.count ?? 0
      )
    }
    if imagesAddedOrRemoved {
      self.continuation.yield()
    }
  }

  /// 증분 정보가 없으면 무엇이 바뀌었는지 알 수 없으므로 알린다. 있으면 추가·삭제가 있을 때만 알린다.
  static func shouldNotify(hasIncrementalChanges: Bool, insertedCount: Int, removedCount: Int) -> Bool {
    guard hasIncrementalChanges else { return true }
    return insertedCount > 0 || removedCount > 0
  }
}
