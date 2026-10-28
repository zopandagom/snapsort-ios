import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 최근 스크린샷 화면: 스크린샷 목록과 보관 (docs/ARCHITECTURE.md §4 저장소·정리 도우미).
extension PhotoStore {
  func captureInboxScreenshots(createdSince since: Date) throws -> [ImageAsset] {
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.isScreenshot && !image.isKeptInCaptureInbox && (image.creationDate.flatMap { $0 >= since } ?? false)
      }
    )
    descriptor.propertiesToFetch = [
      \.assetID, \.creationDate, \.latitude, \.longitude, \.pixelWidth, \.pixelHeight, \.isScreenshot,
    ]
    return try self.modelContext.fetch(descriptor).sorted(by: Self.isNewer).map(Self.imageAsset)
  }

  func keepInCaptureInbox(id: ImageAsset.ID) throws -> Bool {
    var changed = false
    try self.write {
      var descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.assetID == id })
      descriptor.fetchLimit = 1
      guard let image = try self.modelContext.fetch(descriptor).first else { return }
      image.isKeptInCaptureInbox = true
      changed = true
    }
    return changed
  }
}
