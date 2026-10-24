import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 검색 목록: 글자를 읽은 행의 메타데이터·OCR 줄·캡처 묶음 값 (docs/ARCHITECTURE.md §4 저장소·검색).
extension PhotoStore {
  /// 줄을 디코딩하지 않은 검색 행. 디코딩은 actor 밖에서 한다(저장소 actor 는 직렬이라 안에서 하면 인덱서 저장·다른 읽기가 막힌다).
  struct SearchRow: Sendable {
    let asset: ImageAsset
    let textLinesData: Data
    let captureGroups: CaptureGroups?
  }

  func searchRows() throws -> (rows: [SearchRow], pendingTextCount: Int) {
    var descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.textLinesData != nil })
    descriptor.propertiesToFetch = [
      \.assetID, \.creationDate, \.latitude, \.longitude, \.pixelWidth, \.pixelHeight, \.isScreenshot,
      \.textLinesData, \.captureGroupRulesVersion, \.shoppingMallID, \.shoppingBrandID, \.chatAppID, \.mapRegionIDs,
    ]
    let rows = try self.modelContext.fetch(descriptor)
      .sorted(by: Self.isNewer)
      .compactMap { stored -> SearchRow? in
        guard let data = stored.textLinesData else { return nil }
        return SearchRow(
          asset: Self.imageAsset(stored),
          textLinesData: data,
          captureGroups: Self.storedCaptureGroups(stored)
        )
      }
    // 같은 actor 호출 안이라 한 시점의 값이다.
    let pending = try self.modelContext.fetchCount(
      FetchDescriptor<StoredImage>(predicate: #Predicate { $0.needsTextRecognition && $0.textLinesData == nil })
    )
    return (rows, pending)
  }
}
