import Core
import PhotoStoreInterface

// 소급 보강 (docs/ARCHITECTURE.md §4 저장소).
extension PhotoStoreClientFake {
  public func gifticonModelFillPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    try self.throwModelFillErrorIfNeeded()
    return self.state.withLock { Set($0.images.values.filter(Self.isModelFillPending).map(\.id)) }
  }

  public func saveGifticonModelFills(
    _ results: [ImageAsset.ID: GifticonModelFillResult]
  ) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    try self.throwModelFillErrorIfNeeded()
    self.state.withLock { state in
      state.savedModelFillBatches.append(results)
      for (id, result) in results {
        // Impl 처럼 보강 대기 행만 바꾼다(마친 행·추출 대기 행은 그대로).
        guard let image = state.images[id], Self.isModelFillPending(image) else {
          continue
        }
        guard let (gifticon, fill) = Self.applied(result, to: image) else {
          continue
        }
        state.images[id] = IndexedImage(
          asset: image.asset,
          labels: image.labels,
          textRecognition: image.textRecognition,
          categories: image.categories,
          gifticon: gifticon,
          gifticonModelFill: fill
        )
      }
    }
  }

  /// 기프티콘으로 분류돼 글자를 읽었고 추출 값이 있는데 보강을 마치지 않았다.
  private static func isModelFillPending(_ image: IndexedImage) -> Bool {
    image.categories.contains(.gifticon) && image.textLines != nil && image.gifticon != nil
      && image.gifticonModelFill != .done
  }

  /// Impl `saveGifticonModelFills` 와 같은 표로 결과를 쓴 뒤의 추출 값과 보강 상태. 무시하는 결과면 nil.
  private static func applied(
    _ result: GifticonModelFillResult,
    to image: IndexedImage
  ) -> (GifticonInfo, GifticonModelFill)? {
    let failures = if case let .pending(failures) = image.gifticonModelFill {
      failures
    } else {
      0
    }
    switch result {
    case let .filled(gifticon):
      return (gifticon, .done)
    case let .failed(rules):
      let counted = failures + 1
      return (rules, counted >= GifticonModelFill.maximumFailures ? .done : .pending(failures: counted))
    case let .deferred(rules):
      return (rules, .pending(failures: failures))
    case let .resolvedSources(info):
      // Impl 처럼 출처를 정하지 않은 행이고 저장된 두 값이 같을 때만 출처를 붙여 마친다.
      guard image.gifticonModelFill == .sourcesUnknown, let stored = image.gifticon,
            stored.expiryDate == info.expiryDate, stored.redemptionPlace == info.redemptionPlace
      else {
        return nil
      }
      return (info, .done)
    }
  }

  private func throwModelFillErrorIfNeeded() throws(PhotoStoreError) {
    if let error = self.modelFillError {
      throw error
    }
  }
}
