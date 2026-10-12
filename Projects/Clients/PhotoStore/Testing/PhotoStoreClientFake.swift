import Core
import PhotoStoreInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 메모리에 저장해 Impl 처럼 저장·삭제·여행 교체가 조회에 반영되고, 저장·삭제 요청을 기록한다.
/// 저장 결과가 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class PhotoStoreClientFake: PhotoStoreClient {
  private let error: PhotoStoreError?
  private let saveLimit: Int?
  private let state: Mutex<State>

  private struct State {
    var images: [ImageAsset.ID: IndexedImage]
    var trips: [Trip]
    var savedBatches: [[IndexedImage]] = []
    var deletedBatches: [Set<ImageAsset.ID>] = []
    var replaceTripsCount = 0
  }

  /// - Parameters:
  ///   - error: 정하면 모든 호출이 이 실패를 던지고 아무것도 바꾸지 않는다.
  ///   - saveLimit: 정하면 `save` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 작업 도중의 저장 실패를 흉내 낸다.
  public init(
    images: [IndexedImage] = [],
    trips: [Trip] = [],
    error: PhotoStoreError? = nil,
    saveLimit: Int? = nil
  ) {
    self.error = error
    self.saveLimit = saveLimit
    self.state = Mutex(State(
      images: Dictionary(images.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }),
      trips: trips
    ))
  }

  /// 지금 저장된 이미지. 식별자 순이다.
  public var images: [IndexedImage] {
    self.state.withLock { $0.images.values.sorted { $0.id < $1.id } }
  }

  /// `save` 에 넘긴 이미지 목록을 부른 순서대로.
  public var savedBatches: [[IndexedImage]] {
    self.state.withLock { $0.savedBatches }
  }

  /// `replaceTrips` 가 성공한 횟수.
  public var replaceTripsCount: Int {
    self.state.withLock { $0.replaceTripsCount }
  }

  /// `delete` 에 넘긴 식별자를 부른 순서대로.
  public var deletedBatches: [Set<ImageAsset.ID>] {
    self.state.withLock { $0.deletedBatches }
  }

  public func save(_ images: [IndexedImage]) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.saveLimit, state.savedBatches.count >= limit {
        return false
      }
      state.savedBatches.append(images)
      for image in images {
        state.images[image.id] = image
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  public func delete(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    self.state.withLock { state in
      state.deletedBatches.append(ids)
      for id in ids {
        state.images[id] = nil
      }
    }
  }

  public func indexedIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    return self.state.withLock { Set($0.images.keys) }
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
    self.state.withLock { state in
      state.trips = trips
      state.replaceTripsCount += 1
    }
  }

  /// Impl 처럼 시작 시각 순(같으면 끝 시각 순)으로 돌려준다.
  public func trips() async throws(PhotoStoreError) -> [Trip] {
    try self.throwIfNeeded()
    return self.state.withLock { $0.trips }.sorted { ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate) }
  }

  private func throwIfNeeded() throws(PhotoStoreError) {
    if let error = self.error {
      throw error
    }
  }
}
