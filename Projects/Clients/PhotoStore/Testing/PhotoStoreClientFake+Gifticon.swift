import Core
import PhotoStoreInterface

// 만료 예정·기프티콘 목록·사용 여부 (docs/ARCHITECTURE.md §4 저장소·만료 알림).
public extension PhotoStoreClientFake {
  /// 프로토콜 약속대로 만료일 오름차순(같으면 식별자 순)으로 돌려준다. 사용한 기프티콘은 뺀다.
  func upcomingGifticonExpiries(from date: LocalDate) async throws(PhotoStoreError) -> [GifticonExpiry] {
    try self.throwIfNeeded()
    let used = self.usedIDs
    let expiries = self.images
      .filter { !used.contains($0.id) }
      .compactMap { image in
        image.gifticon?.expiryDate.flatMap { $0 >= date ? GifticonExpiry(imageID: image.id, expiryDate: $0) : nil }
      }
      .sorted { ($0.expiryDate, $0.imageID) < ($1.expiryDate, $1.imageID) }
    let index = self.state.withLock { state in
      defer { state.upcomingGifticonExpiriesCount += 1 }
      return state.upcomingGifticonExpiriesCount
    }
    await self.onUpcomingGifticonExpiries(index)
    return expiries
  }

  /// 지금 사용함인 이미지.
  var usedIDs: Set<ImageAsset.ID> {
    self.state.withLock { $0.usedIDs }
  }

  /// `setGifticonUsed` 를 부른 횟수. 실패한 호출도 센다.
  var setGifticonUsedCount: Int {
    self.state.withLock { $0.setGifticonUsedCount }
  }

  /// `gifticons()` 를 부른 횟수. `gifticonsErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var gifticonsCallCount: Int {
    self.state.withLock { $0.gifticonsCallCount }
  }

  /// 프로토콜 약속대로 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  func gifticons() async throws(PhotoStoreError) -> [GifticonListItem] {
    try self.throwIfNeeded()
    let (index, items) = self.state.withLock { state in
      defer { state.gifticonsCallCount += 1 }
      let items = state.images.values
        .filter { $0.categories.contains(.gifticon) }
        .sorted(by: Self.isNewer)
        .map { Self.listItem($0, isUsed: state.usedIDs.contains($0.id)) }
      return (state.gifticonsCallCount, items)
    }
    if let error = self.gifticonsErrors[index] {
      throw error
    }
    await self.onGifticons(index)
    return items
  }

  func gifticon(id: ImageAsset.ID) async throws(PhotoStoreError) -> GifticonListItem? {
    try self.throwIfNeeded()
    let (index, item) = self.state.withLock { state in
      defer { state.gifticonCallCount += 1 }
      let item = state.images[id].flatMap { image in
        image.categories.contains(.gifticon) ? Self.listItem(image, isUsed: state.usedIDs.contains(id)) : nil
      }
      return (state.gifticonCallCount, item)
    }
    await self.onGifticon(index)
    return item
  }

  func setGifticonUsed(_ isUsed: Bool, id: ImageAsset.ID) async throws(PhotoStoreError) -> Bool {
    let index = self.state.withLock { state in
      defer { state.setGifticonUsedCount += 1 }
      return state.setGifticonUsedCount
    }
    await self.onSetGifticonUsed(index)
    try self.throwIfNeeded()
    if let error = self.setUsedError {
      throw error
    }
    return self.state.withLock { state in
      guard state.images[id]?.categories.contains(.gifticon) ?? false else {
        return false
      }
      if isUsed {
        state.usedIDs.insert(id)
      } else {
        state.usedIDs.remove(id)
      }
      return true
    }
  }

  /// Impl `gifticons()` 와 같은 표로 만든 목록 항목.
  private static func listItem(_ image: IndexedImage, isUsed: Bool) -> GifticonListItem {
    let status: GifticonListItem.Status = if let gifticon = image.gifticon {
      .extracted(gifticon)
    } else if image.textRecognition == .notNeeded {
      .extracted(GifticonInfo(expiryDate: nil, redemptionPlace: nil))
    } else {
      .checking
    }
    return GifticonListItem(
      asset: image.asset,
      status: status,
      isUsed: isUsed,
      valuesMayBeFromModel: image.gifticonModelFill == .stale || image.gifticonModelFill == .sourcesUnknown
    )
  }
}
