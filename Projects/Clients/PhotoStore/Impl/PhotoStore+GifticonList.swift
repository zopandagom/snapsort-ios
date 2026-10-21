import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 기프티콘 목록·사용 여부 (docs/ARCHITECTURE.md §4 저장소).
extension PhotoStore {
  func gifticons() throws -> [GifticonListItem] {
    let rawValue = ImageCategory.gifticon.rawValue
    let stored = try self.modelContext.fetch(
      FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          image.memberships.contains { $0.category == rawValue }
        }
      )
    )
    return stored.sorted(by: Self.isNewer).map(Self.gifticonListItem)
  }

  func gifticon(id: ImageAsset.ID) throws -> GifticonListItem? {
    let rawValue = ImageCategory.gifticon.rawValue
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.assetID == id && image.memberships.contains { $0.category == rawValue }
      }
    )
    descriptor.fetchLimit = 1
    return try self.modelContext.fetch(descriptor).first.map(Self.gifticonListItem)
  }

  func setGifticonUsed(_ isUsed: Bool, id: ImageAsset.ID) throws -> Bool {
    var changed = false
    try self.write {
      let rawValue = ImageCategory.gifticon.rawValue
      var descriptor = FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          image.assetID == id && image.memberships.contains { $0.category == rawValue }
        }
      )
      descriptor.fetchLimit = 1
      guard let image = try self.modelContext.fetch(descriptor).first else {
        return
      }
      image.gifticonIsUsed = isUsed
      changed = true
    }
    return changed
  }

  /// 기프티콘 카테고리 행의 목록 항목. 줄을 디코딩하지 않고 OCR 상태는 `needsTextRecognition`·`textLinesData` 유무로 본다.
  /// 추출 값이 있으면 `.extracted`, 없고 OCR 대기·추출 대기면 `.checking`, OCR 대상이 아니면 찾을 값이 없어 빈 추출 값이다.
  private static func gifticonListItem(_ stored: StoredImage) -> GifticonListItem {
    let status: GifticonListItem.Status = if let gifticon = Self.storedGifticon(stored) {
      .extracted(gifticon)
    } else if stored.needsTextRecognition || stored.textLinesData != nil {
      .checking
    } else {
      .extracted(GifticonInfo(expiryDate: nil, redemptionPlace: nil))
    }
    let fill = Self.modelFill(stored)
    return GifticonListItem(
      asset: Self.imageAsset(stored),
      status: status,
      isUsed: stored.gifticonIsUsed,
      valuesMayBeFromModel: fill == .stale || fill == .sourcesUnknown
    )
  }
}
