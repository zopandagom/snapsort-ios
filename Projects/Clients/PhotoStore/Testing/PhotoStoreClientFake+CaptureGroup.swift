import Core
import PhotoStoreInterface

// 캡처 묶음 값 소급과 쇼핑·대화·지도 목록 (docs/ARCHITECTURE.md §4 저장소).
public extension PhotoStoreClientFake {
  /// `saveCaptureGroups` 에 넘긴 묶음 값을 부른 순서대로. 실패한 호출은 빠진다.
  var savedCaptureGroupBatches: [[ImageAsset.ID: CaptureGroups]] {
    self.state.withLock { $0.captureGroup.savedBatches }
  }

  /// `captureGroupItems(in:)` 를 부른 횟수. `captureGroupItemsErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var captureGroupItemsCallCount: Int {
    self.state.withLock { $0.captureGroup.itemsCallCount }
  }

  func captureGroupExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    try self.throwCaptureGroupErrorIfNeeded()
    return self.state.withLock { Set($0.images.values.filter(Self.isCaptureGroupExtractionPending).map(\.id)) }
  }

  func saveCaptureGroups(_ groups: [ImageAsset.ID: CaptureGroups]) async throws(PhotoStoreError) {
    await self.captureGroupOptions.onSave(groups)
    try self.throwIfNeeded()
    try self.throwCaptureGroupErrorIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.captureGroupOptions.saveLimit, state.captureGroup.savedBatches.count >= limit {
        return false
      }
      state.captureGroup.savedBatches.append(groups)
      for (id, value) in groups {
        // Impl 처럼 추출 대기 행만 바꾼다(이미 추출한 행은 덮지 않는다). 기프티콘·영수증 값은 그대로 둔다.
        guard let image = state.images[id], Self.isCaptureGroupExtractionPending(image) else {
          continue
        }
        state.images[id] = IndexedImage(
          asset: image.asset,
          labels: image.labels,
          textRecognition: image.textRecognition,
          categories: image.categories,
          gifticon: image.gifticon,
          gifticonModelFill: image.gifticonModelFill,
          receipt: image.receipt,
          // 행 카테고리로 제한하는 것은 `IndexedImage.init` 이 한다.
          captureGroups: value,
          featurePrint: image.featurePrint
        )
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  /// 프로토콜 약속대로 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  func captureGroupItems(in category: ImageCategory) async throws(PhotoStoreError) -> [CaptureGroupItem] {
    try self.throwIfNeeded()
    let (index, items) = self.state.withLock { state in
      defer { state.captureGroup.itemsCallCount += 1 }
      let items = state.images.values
        .filter { CaptureGroupExtractor.categories.contains(category) && $0.categories.contains(category) }
        .sorted(by: Self.isNewer)
        .map(Self.captureGroupItem)
      return (state.captureGroup.itemsCallCount, items)
    }
    if let error = self.captureGroupOptions.itemsErrors[index] {
      throw error
    }
    await self.captureGroupOptions.onItems(index)
    return items
  }

  /// Impl `captureGroupItems(in:)` 와 같은 표로 만든 목록 항목.
  private static func captureGroupItem(_ image: IndexedImage) -> CaptureGroupItem {
    let status: CaptureGroupItem.Status = if let groups = image.captureGroups {
      .extracted(groups)
    } else if image.textRecognition == .notNeeded {
      .extracted(.empty)
    } else {
      .checking
    }
    return CaptureGroupItem(asset: image.asset, status: status)
  }

  /// 쇼핑·대화·지도 중 하나로 분류돼 글자를 읽었는데 묶음 값이 없다.
  private static func isCaptureGroupExtractionPending(_ image: IndexedImage) -> Bool {
    !image.categories.isDisjoint(with: CaptureGroupExtractor.categories) && image.textLines != nil
      && image.captureGroups == nil
  }

  private func throwCaptureGroupErrorIfNeeded() throws(PhotoStoreError) {
    if let error = self.captureGroupOptions.error {
      throw error
    }
  }
}

extension PhotoStoreClientFake {
  /// 캡처 묶음용 실패·훅.
  struct CaptureGroupOptions {
    /// 정하면 `captureGroupExtractionPendingIDs`·`saveCaptureGroups` 만 이 실패를 던지고 묶음 값을 바꾸지 않는다. 다른 호출은 성공한다.
    /// 캡처 묶음 소급 대상 조회·저장만의 실패를 흉내 낸다.
    let error: PhotoStoreError?
    /// 정하면 `saveCaptureGroups` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 캡처 묶음 소급 도중의 저장 실패를 흉내 낸다.
    let saveLimit: Int?
    /// `saveCaptureGroups` 가 오류·한도 확인과 쓰기 전에 기다려 부른다. 캡처 묶음 소급 배치 도중(저장 직전)에 보관함이 바뀌는 일을 흉내 낸다.
    let onSave: @Sendable ([ImageAsset.ID: CaptureGroups]) async -> Void
    /// `captureGroupItems(in:)` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
    /// `error`(모든 호출)가 정해져 있으면 그것이 먼저다.
    let itemsErrors: [Int: PhotoStoreError]
    /// `captureGroupItems(in:)` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
    /// 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
    let onItems: @Sendable (Int) async -> Void
  }

  /// 캡처 묶음용 기록.
  struct CaptureGroupState {
    var savedBatches: [[ImageAsset.ID: CaptureGroups]] = []
    var itemsCallCount = 0
  }
}
