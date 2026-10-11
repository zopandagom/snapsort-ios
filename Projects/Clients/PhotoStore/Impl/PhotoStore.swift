import Core
import Foundation
import PhotoStoreInterface
import SwiftData

/// SwiftData 읽기·쓰기. `@Model` 객체는 Sendable 이 아니므로 이 actor 밖으로 내보내지 않고 값 타입으로 바꿔 돌려준다.
@ModelActor
actor PhotoStore {
  func save(_ images: [IndexedImage]) throws {
    try self.write {
      // 같은 배치에 같은 식별자가 여러 번 오면 마지막 결과를 쓴다.
      let latest = Dictionary(images.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
      let ids = Array(latest.keys)
      let existing = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      let existingByID = Dictionary(existing.map { ($0.assetID, $0) }, uniquingKeysWith: { first, _ in first })
      let encoder = PropertyListEncoder()
      for image in latest.values {
        let stored: StoredImage
        if let found = existingByID[image.id] {
          stored = found
          for membership in found.memberships {
            self.modelContext.delete(membership)
          }
          found.memberships = []
        } else {
          stored = StoredImage(assetID: image.id)
          self.modelContext.insert(stored)
        }
        stored.creationDate = image.asset.creationDate
        stored.latitude = image.asset.coordinate?.latitude
        stored.longitude = image.asset.coordinate?.longitude
        stored.pixelWidth = image.asset.pixelWidth
        stored.pixelHeight = image.asset.pixelHeight
        stored.isScreenshot = image.asset.isScreenshot
        stored.labelsData = try encoder.encode(image.labels)
        stored.textLinesData = try image.textLines.map { try encoder.encode($0) }
        // 여행은 `StoredTrip` 으로 다루므로 카테고리 행으로 두지 않는다. 순서를 고정해 같은 입력이면 같은 행이 되게 한다.
        stored.memberships = image.categories.subtracting([.travel]).map(\.rawValue).sorted()
          .map(StoredCategoryMembership.init)
      }
    }
  }

  func delete(ids: Set<ImageAsset.ID>) throws {
    try self.write {
      let ids = Array(ids)
      // 일괄 삭제(`delete(model:where:)`)가 아니라 하나씩 지워 카테고리 행도 함께 지워지게 한다.
      let stored = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      for image in stored {
        self.modelContext.delete(image)
      }
    }
  }

  func indexedIDs() throws -> Set<ImageAsset.ID> {
    var descriptor = FetchDescriptor<StoredImage>()
    descriptor.propertiesToFetch = [\.assetID]
    return try Set(self.modelContext.fetch(descriptor).map(\.assetID))
  }

  func images(in category: ImageCategory) throws -> [IndexedImage] {
    let rawValue = category.rawValue
    let stored = try self.modelContext.fetch(
      FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          image.memberships.contains { $0.category == rawValue }
        }
      )
    )
    let decoder = PropertyListDecoder()
    return try stored
      .sorted(by: Self.isNewer)
      .map { try Self.indexedImage($0, decoder: decoder) }
  }

  func categoryCounts() throws -> [ImageCategory: Int] {
    var counts: [ImageCategory: Int] = [:]
    for category in ImageCategory.allCases {
      let rawValue = category.rawValue
      let count = try self.modelContext.fetchCount(
        FetchDescriptor<StoredCategoryMembership>(predicate: #Predicate { $0.category == rawValue })
      )
      if count > 0 {
        counts[category] = count
      }
    }
    return counts
  }

  func replaceTrips(_ trips: [Trip]) throws {
    try self.write {
      for stored in try self.modelContext.fetch(FetchDescriptor<StoredTrip>()) {
        self.modelContext.delete(stored)
      }
      for trip in trips {
        self.modelContext.insert(
          StoredTrip(
            assetIDs: trip.assetIDs,
            startDate: trip.startDate,
            endDate: trip.endDate,
            centerLatitude: trip.center.latitude,
            centerLongitude: trip.center.longitude
          )
        )
      }
    }
  }

  func trips() throws -> [Trip] {
    try self.modelContext
      .fetch(FetchDescriptor<StoredTrip>(sortBy: [SortDescriptor(\.startDate), SortDescriptor(\.endDate)]))
      .map { stored in
        Trip(
          assetIDs: stored.assetIDs,
          startDate: stored.startDate,
          endDate: stored.endDate,
          center: Coordinate(latitude: stored.centerLatitude, longitude: stored.centerLongitude)
        )
      }
  }

  /// 변경을 저장한다. 도중에 실패하면 저장하지 않은 변경을 되돌려, 다음 조회·저장에 반쯤 끝난 상태가 남지 않게 한다.
  private func write(_ changes: () throws -> Void) throws {
    do {
      try changes()
      try self.modelContext.save()
    } catch {
      self.modelContext.rollback()
      throw error
    }
  }

  /// 최신순. 생성일이 없으면 맨 뒤, 같으면 식별자 순으로 고정한다.
  private static func isNewer(_ lhs: StoredImage, than rhs: StoredImage) -> Bool {
    switch (lhs.creationDate, rhs.creationDate) {
    case let (left?, right?) where left != right:
      left > right
    case (.some, nil):
      true
    case (nil, .some):
      false
    default:
      lhs.assetID < rhs.assetID
    }
  }

  private static func indexedImage(_ stored: StoredImage, decoder: PropertyListDecoder) throws -> IndexedImage {
    let coordinate: Coordinate? = if let latitude = stored.latitude, let longitude = stored.longitude {
      Coordinate(latitude: latitude, longitude: longitude)
    } else {
      nil
    }
    return try IndexedImage(
      asset: ImageAsset(
        id: stored.assetID,
        creationDate: stored.creationDate,
        coordinate: coordinate,
        pixelWidth: stored.pixelWidth,
        pixelHeight: stored.pixelHeight,
        isScreenshot: stored.isScreenshot
      ),
      labels: decoder.decode([ImageLabel].self, from: stored.labelsData),
      textLines: stored.textLinesData.map { try decoder.decode([RecognizedTextLine].self, from: $0) },
      categories: Set(stored.memberships.compactMap { ImageCategory(rawValue: $0.category) })
    )
  }
}
