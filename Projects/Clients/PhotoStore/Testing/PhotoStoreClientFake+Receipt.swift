import Core
import PhotoStoreInterface

// 영수증 추출 값 소급과 영수증 목록 (docs/ARCHITECTURE.md §4 저장소).
public extension PhotoStoreClientFake {
  /// `saveReceipts` 에 넘긴 추출 값을 부른 순서대로. 실패한 호출은 빠진다.
  var savedReceiptBatches: [[ImageAsset.ID: ReceiptInfo]] {
    self.state.withLock { $0.receipt.savedBatches }
  }

  /// `receipts()` 를 부른 횟수. `receiptsErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var receiptsCallCount: Int {
    self.state.withLock { $0.receipt.receiptsCallCount }
  }

  func receiptExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    try self.throwReceiptErrorIfNeeded()
    return self.state.withLock { Set($0.images.values.filter(Self.isReceiptExtractionPending).map(\.id)) }
  }

  func saveReceipts(_ receipts: [ImageAsset.ID: ReceiptInfo]) async throws(PhotoStoreError) {
    await self.receiptOptions.onSave(receipts)
    try self.throwIfNeeded()
    try self.throwReceiptErrorIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.receiptOptions.saveLimit, state.receipt.savedBatches.count >= limit {
        return false
      }
      state.receipt.savedBatches.append(receipts)
      for (id, receipt) in receipts {
        // Impl 처럼 추출 대기 행만 바꾼다(이미 추출한 행은 덮지 않는다). 기프티콘 값·보강 상태는 그대로 둔다.
        guard let image = state.images[id], Self.isReceiptExtractionPending(image) else {
          continue
        }
        state.images[id] = IndexedImage(
          asset: image.asset,
          labels: image.labels,
          textRecognition: image.textRecognition,
          categories: image.categories,
          gifticon: image.gifticon,
          gifticonModelFill: image.gifticonModelFill,
          receipt: receipt,
          captureGroups: image.captureGroups
        )
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  /// 프로토콜 약속대로 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  func receipts() async throws(PhotoStoreError) -> [ReceiptListItem] {
    try self.throwIfNeeded()
    let (index, items) = self.state.withLock { state in
      defer { state.receipt.receiptsCallCount += 1 }
      let items = state.images.values
        .filter { $0.categories.contains(.receipt) }
        .sorted(by: Self.isNewer)
        .map(Self.receiptListItem)
      return (state.receipt.receiptsCallCount, items)
    }
    if let error = self.receiptOptions.receiptsErrors[index] {
      throw error
    }
    await self.receiptOptions.onReceipts(index)
    return items
  }

  /// Impl `receipts()` 와 같은 표로 만든 목록 항목.
  private static func receiptListItem(_ image: IndexedImage) -> ReceiptListItem {
    let status: ReceiptListItem.Status = if let receipt = image.receipt {
      .extracted(receipt)
    } else if image.textRecognition == .notNeeded {
      .extracted(.empty)
    } else {
      .checking
    }
    return ReceiptListItem(asset: image.asset, status: status)
  }

  /// 영수증으로 분류돼 글자를 읽었는데 추출 값이 없다.
  private static func isReceiptExtractionPending(_ image: IndexedImage) -> Bool {
    image.categories.contains(.receipt) && image.textLines != nil && image.receipt == nil
  }

  private func throwReceiptErrorIfNeeded() throws(PhotoStoreError) {
    if let error = self.receiptOptions.error {
      throw error
    }
  }
}

extension PhotoStoreClientFake {
  /// 영수증용 실패·훅.
  struct ReceiptOptions {
    /// 정하면 `receiptExtractionPendingIDs`·`saveReceipts` 만 이 실패를 던지고 추출 값을 바꾸지 않는다. 다른 호출은 성공한다.
    /// 영수증 소급 대상 조회·저장만의 실패를 흉내 낸다.
    let error: PhotoStoreError?
    /// 정하면 `saveReceipts` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 영수증 소급 도중의 저장 실패를 흉내 낸다.
    let saveLimit: Int?
    /// `saveReceipts` 가 오류·한도 확인과 쓰기 전에 기다려 부른다. 영수증 소급 배치 도중(저장 직전)에 보관함이 바뀌는 일을 흉내 낸다.
    let onSave: @Sendable ([ImageAsset.ID: ReceiptInfo]) async -> Void
    /// `receipts()` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
    /// `error`(모든 호출)가 정해져 있으면 그것이 먼저다.
    let receiptsErrors: [Int: PhotoStoreError]
    /// `receipts()` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
    /// 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
    let onReceipts: @Sendable (Int) async -> Void
  }

  /// 영수증용 기록.
  struct ReceiptState {
    var savedBatches: [[ImageAsset.ID: ReceiptInfo]] = []
    var receiptsCallCount = 0
  }
}
