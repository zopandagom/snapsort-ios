import Core
import PhotoStoreInterface

// 특징 벡터 소급과 비슷한 사진 묶기 입력 (docs/ARCHITECTURE.md §4 저장소·정리 도우미).
public extension PhotoStoreClientFake {
  /// `saveFeaturePrints` 에 넘긴 벡터를 부른 순서대로. 실패한 호출은 빠진다.
  var savedFeaturePrintBatches: [[ImageAsset.ID: ImageFeaturePrint]] {
    self.state.withLock { $0.similarPhoto.savedBatches }
  }

  /// `featurePrintPendingIDs()` 를 부른 횟수. `featurePrintError`·`error` 로 던진 호출도 센다.
  /// 벡터를 쓸 수 없는 기기에서 인덱서가 대기 조회를 하지 않는지 테스트가 센다.
  var featurePrintPendingIDsCallCount: Int {
    self.state.withLock { $0.similarPhoto.pendingCallCount }
  }

  /// `similarPhotoEntries()` 를 부른 횟수. `similarPhotoEntriesErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var similarPhotoEntriesCallCount: Int {
    self.state.withLock { $0.similarPhoto.entriesCallCount }
  }

  func featurePrintPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    self.state.withLock { $0.similarPhoto.pendingCallCount += 1 }
    try self.throwIfNeeded()
    try self.throwFeaturePrintErrorIfNeeded()
    return self.state.withLock { Set($0.images.values.filter(Self.isFeaturePrintPending).map(\.id)) }
  }

  func saveFeaturePrints(_ prints: [ImageAsset.ID: ImageFeaturePrint]) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    try self.throwFeaturePrintErrorIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.similar.saveLimit, state.similarPhoto.savedBatches.count >= limit {
        return false
      }
      state.similarPhoto.savedBatches.append(prints)
      for (id, featurePrint) in prints {
        // Impl 처럼 대기 행만 바꾼다(이미 벡터가 있는 행은 덮지 않는다).
        guard let image = state.images[id], Self.isFeaturePrintPending(image) else {
          continue
        }
        state.images[id] = Self.replacingFeaturePrint(of: image, with: featurePrint)
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  /// Impl 과 같은 표: 벡터가 있는 대상 사진 중 시간 이웃이 있는 것을 생성일 오름차순(같으면 식별자 순)으로, 미비교 수는 대기 수.
  func similarPhotoEntries() async throws(PhotoStoreError) -> SimilarPhotoEntries {
    try self.throwIfNeeded()
    let (index, result) = self.state.withLock { state in
      defer { state.similarPhoto.entriesCallCount += 1 }
      let printed = state.images.values
        .compactMap { image in image.featurePrint.map { FeaturePrintedPhoto(asset: image.asset, featurePrint: $0) } }
        .sorted { lhs, rhs in
          let lhsDate = lhs.asset.creationDate ?? .distantPast
          let rhsDate = rhs.asset.creationDate ?? .distantPast
          return lhsDate != rhsDate ? lhsDate < rhsDate : lhs.id < rhs.id
        }
      let linkable = SimilarPhotoGrouping.linkableIDs(in: printed.map(\.asset))
      let pending = state.images.values.count(where: Self.isFeaturePrintPending)
      return (
        state.similarPhoto.entriesCallCount,
        SimilarPhotoEntries(photos: printed.filter { linkable.contains($0.id) }, uncomparedCount: pending)
      )
    }
    if let error = self.similar.entriesErrors[index] {
      throw error
    }
    await self.similar.onEntries(index)
    return result
  }

  /// 벡터 대상인데 벡터가 없다.
  private static func isFeaturePrintPending(_ image: IndexedImage) -> Bool {
    ImageFeaturePrint.isTarget(image.asset, needsTextRecognition: image.textRecognition != .notNeeded)
      && image.featurePrint == nil
  }

  private func throwFeaturePrintErrorIfNeeded() throws(PhotoStoreError) {
    if let error = self.similar.featurePrintError {
      throw error
    }
  }
}

extension PhotoStoreClientFake {
  /// 특징 벡터 소급·비슷한 사진 읽기용 실패·훅.
  struct SimilarPhotoOptions {
    /// `similarPhotoEntries()` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
    /// `error`(모든 호출)가 정해져 있으면 그것이 먼저다.
    let entriesErrors: [Int: PhotoStoreError]
    /// `similarPhotoEntries()` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
    /// 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
    let onEntries: @Sendable (Int) async -> Void
    /// 정하면 `featurePrintPendingIDs`·`saveFeaturePrints` 만 이 실패를 던지고 벡터를 바꾸지 않는다. 다른 호출은 성공한다.
    /// 벡터 소급 대상 조회·저장만의 실패를 흉내 낸다.
    let featurePrintError: PhotoStoreError?
    /// 정하면 `saveFeaturePrints` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 벡터 소급 도중의 저장 실패를 흉내 낸다.
    let saveLimit: Int?

    /// Fake init 의 인자
    /// 순서(`similarPhotoEntriesErrors`·`onSimilarPhotoEntries`·`featurePrintError`·`featurePrintSaveLimit`).
    init(
      _ entriesErrors: [Int: PhotoStoreError],
      _ onEntries: @escaping @Sendable (Int) async -> Void,
      _ featurePrintError: PhotoStoreError?,
      _ saveLimit: Int?
    ) {
      self.entriesErrors = entriesErrors
      self.onEntries = onEntries
      self.featurePrintError = featurePrintError
      self.saveLimit = saveLimit
    }
  }

  /// 특징 벡터·비슷한 사진용 기록.
  struct SimilarPhotoState {
    var savedBatches: [[ImageAsset.ID: ImageFeaturePrint]] = []
    var pendingCallCount = 0
    var entriesCallCount = 0
  }

  /// 벡터만 바꾼 이미지. 대상이 아니면 `IndexedImage.init` 이 nil 로 둔다.
  static func replacingFeaturePrint(of image: IndexedImage, with featurePrint: ImageFeaturePrint?) -> IndexedImage {
    IndexedImage(
      asset: image.asset,
      labels: image.labels,
      textRecognition: image.textRecognition,
      categories: image.categories,
      gifticon: image.gifticon,
      gifticonModelFill: image.gifticonModelFill,
      receipt: image.receipt,
      captureGroups: image.captureGroups,
      featurePrint: featurePrint
    )
  }
}
