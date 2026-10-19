import Core
import PhotoStoreInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 메모리에 저장해 Impl 처럼 저장·삭제·추출 값 저장·여행 교체가 조회에 반영되고,
/// 저장·삭제·추출 값 저장 요청을 기록한다. 추출 규칙 버전은 두지 않는다(버전 동작은 Impl 테스트가 본다).
/// 모든 호출의 실패와 따로, 소급 추출 호출만의 실패(`gifticonError`)와 특정 식별자를 읽는 `images(ids:)` 만의 실패
/// (`failingOnIDRead`)도 정할 수 있다.
/// 저장 결과가 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class PhotoStoreClientFake: PhotoStoreClient {
  private let error: PhotoStoreError?
  private let saveLimit: Int?
  private let gifticonSaveLimit: Int?
  private let gifticonError: PhotoStoreError?
  private let failingOnIDRead: Set<ImageAsset.ID>
  private let onSaveGifticons: @Sendable ([ImageAsset.ID: GifticonInfo]) async -> Void
  private let state: Mutex<State>

  private struct State {
    var images: [ImageAsset.ID: IndexedImage]
    var trips: [Trip]
    var savedBatches: [[IndexedImage]] = []
    var savedGifticonBatches: [[ImageAsset.ID: GifticonInfo]] = []
    var deletedBatches: [Set<ImageAsset.ID>] = []
    var replaceTripsCount = 0
    var missingOnIDRead: Set<ImageAsset.ID> = []
  }

  /// - Parameters:
  ///   - error: 정하면 모든 호출이 이 실패를 던지고 아무것도 바꾸지 않는다.
  ///   - saveLimit: 정하면 `save` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 작업 도중의 저장 실패를 흉내 낸다.
  ///   - gifticonSaveLimit: 정하면 `saveGifticons` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 소급 추출 도중의 저장 실패를 흉내 낸다.
  ///   - gifticonError: 정하면 `gifticonExtractionPendingIDs`·`saveGifticons` 만 이 실패를 던지고 추출 값을 바꾸지 않는다.
  ///     다른 호출은 성공한다. 소급 추출 대상 조회·저장만의 실패를 흉내 낸다(`error` 는 그 앞의 다른 호출에서 먼저 멈춘다).
  ///   - missingOnIDRead: `images(ids:)` 가 빼고 돌려줄 식별자. 다른 조회에는 있는데 읽을 때 행이 없는 어긋남을 흉내 낸다.
  ///     `restoreIDReads()` 로 푼다.
  ///   - failingOnIDRead: `images(ids:)` 가 이 식별자를 하나라도 요청받으면 `.failed` 를 던진다. 다른 호출과 겹치지 않는 읽기는
  ///     성공한다. 소급 배치처럼 그 식별자를 읽는 호출만 실패하는 경우를 흉내 낸다(2단계 배치와는 대상 식별자가 겹치지 않아 구분된다).
  ///   - onSaveGifticons: `saveGifticons` 가 오류·한도 확인과 쓰기 전에 기다려 부른다. 소급 추출 배치 도중(저장 직전)에
  ///     보관함이 바뀌는 일을 흉내 낸다. 소급은 이미지 로드·OCR 을 하지 않아 그쪽 대역의 훅이 걸리지 않는다.
  public init(
    images: [IndexedImage] = [],
    trips: [Trip] = [],
    error: PhotoStoreError? = nil,
    saveLimit: Int? = nil,
    gifticonSaveLimit: Int? = nil,
    gifticonError: PhotoStoreError? = nil,
    missingOnIDRead: Set<ImageAsset.ID> = [],
    failingOnIDRead: Set<ImageAsset.ID> = [],
    onSaveGifticons: @escaping @Sendable ([ImageAsset.ID: GifticonInfo]) async -> Void = { _ in }
  ) {
    self.error = error
    self.saveLimit = saveLimit
    self.gifticonSaveLimit = gifticonSaveLimit
    self.gifticonError = gifticonError
    self.failingOnIDRead = failingOnIDRead
    self.onSaveGifticons = onSaveGifticons
    self.state = Mutex(State(
      images: Dictionary(images.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }),
      trips: trips,
      missingOnIDRead: missingOnIDRead
    ))
  }

  /// `missingOnIDRead` 를 비워 `images(ids:)` 가 다시 모두 돌려주게 한다.
  public func restoreIDReads() {
    self.state.withLock { $0.missingOnIDRead = [] }
  }

  /// 지금 저장된 이미지. 식별자 순이다.
  public var images: [IndexedImage] {
    self.state.withLock { $0.images.values.sorted { $0.id < $1.id } }
  }

  /// `save` 에 넘긴 이미지 목록을 부른 순서대로.
  public var savedBatches: [[IndexedImage]] {
    self.state.withLock { $0.savedBatches }
  }

  /// `saveGifticons` 에 넘긴 추출 값을 부른 순서대로. 실패한 호출은 빠진다.
  public var savedGifticonBatches: [[ImageAsset.ID: GifticonInfo]] {
    self.state.withLock { $0.savedGifticonBatches }
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

  public func pendingTextRecognitionIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    return self.state.withLock { Set($0.images.values.filter { $0.textRecognition == .pending }.map(\.id)) }
  }

  public func gifticonExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    try self.throwGifticonErrorIfNeeded()
    return self.state.withLock { Set($0.images.values.filter(Self.isGifticonExtractionPending).map(\.id)) }
  }

  public func saveGifticons(_ gifticons: [ImageAsset.ID: GifticonInfo]) async throws(PhotoStoreError) {
    await self.onSaveGifticons(gifticons)
    try self.throwIfNeeded()
    try self.throwGifticonErrorIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.gifticonSaveLimit, state.savedGifticonBatches.count >= limit {
        return false
      }
      state.savedGifticonBatches.append(gifticons)
      for (id, gifticon) in gifticons {
        // Impl 처럼 추출 대기 행만 바꾼다(이미 추출한 행은 덮지 않는다).
        guard let image = state.images[id], Self.isGifticonExtractionPending(image) else {
          continue
        }
        state.images[id] = IndexedImage(
          asset: image.asset,
          labels: image.labels,
          textRecognition: image.textRecognition,
          categories: image.categories,
          gifticon: gifticon
        )
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  public func images(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) -> [IndexedImage] {
    try self.throwIfNeeded()
    if !ids.isDisjoint(with: self.failingOnIDRead) {
      throw .failed
    }
    let missing = self.state.withLock { $0.missingOnIDRead }
    return self.images.filter { ids.contains($0.id) && !missing.contains($0.id) }
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

  public func tripCount() async throws(PhotoStoreError) -> Int {
    try self.throwIfNeeded()
    return self.state.withLock { $0.trips.count }
  }

  /// 기프티콘으로 분류돼 글자를 읽었는데 추출 값이 없다.
  private static func isGifticonExtractionPending(_ image: IndexedImage) -> Bool {
    image.categories.contains(.gifticon) && image.textLines != nil && image.gifticon == nil
  }

  private func throwIfNeeded() throws(PhotoStoreError) {
    if let error = self.error {
      throw error
    }
  }

  private func throwGifticonErrorIfNeeded() throws(PhotoStoreError) {
    if let error = self.gifticonError {
      throw error
    }
  }
}
