import Core
import PhotoStoreInterface

/// 테스트와 Example 앱용 대역. 저장·삭제는 무시하고, 조회는 정해 둔 값을 돌려준다.
public struct PhotoStoreClientFake: PhotoStoreClient {
  public let images: [IndexedImage]
  public let storedTrips: [Trip]
  public let error: PhotoStoreError?

  /// - Parameter error: 정하면 모든 호출이 이 실패를 던진다.
  public init(images: [IndexedImage] = [], trips: [Trip] = [], error: PhotoStoreError? = nil) {
    self.images = images
    self.storedTrips = trips
    self.error = error
  }

  public func save(_ images: [IndexedImage]) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
  }

  public func delete(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
  }

  public func indexedIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    return Set(self.images.map(\.id))
  }

  /// 프로토콜 약속대로 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  public func images(in category: ImageCategory) async throws(PhotoStoreError) -> [IndexedImage] {
    try self.throwIfNeeded()
    return self.images
      // Impl 처럼 `.travel` 은 이미지 카테고리로 다루지 않는다.
      .filter { category != .travel && $0.categories.contains(category) }
      .sorted { lhs, rhs in
        switch (lhs.asset.creationDate, rhs.asset.creationDate) {
        case let (left?, right?) where left != right:
          left > right
        case (.some, nil):
          true
        case (nil, .some):
          false
        default:
          lhs.id < rhs.id
        }
      }
  }

  public func categoryCounts() async throws(PhotoStoreError) -> [ImageCategory: Int] {
    try self.throwIfNeeded()
    return self.images.flatMap(\.categories).filter { $0 != .travel }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }

  public func replaceTrips(_ trips: [Trip]) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
  }

  public func trips() async throws(PhotoStoreError) -> [Trip] {
    try self.throwIfNeeded()
    return self.storedTrips
  }

  private func throwIfNeeded() throws(PhotoStoreError) {
    if let error = self.error {
      throw error
    }
  }
}
