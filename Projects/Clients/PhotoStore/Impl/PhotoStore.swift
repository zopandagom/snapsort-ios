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
        switch image.textRecognition {
        case .notNeeded:
          stored.needsTextRecognition = false
          stored.textLinesData = nil
        case .pending:
          stored.needsTextRecognition = true
          stored.textLinesData = nil
        case let .recognized(lines):
          stored.needsTextRecognition = true
          stored.textLinesData = try encoder.encode(lines)
        }
        // 여행은 `StoredTrip` 으로 다루므로 카테고리 행으로 두지 않는다. 순서를 고정해 같은 입력이면 같은 행이 되게 한다.
        stored.memberships = image.categories.subtracting([.travel]).map(\.rawValue).sorted()
          .map(StoredCategoryMembership.init)
        Self.setGifticon(image.gifticon, on: stored)
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

  func pendingTextRecognitionIDs() throws -> Set<ImageAsset.ID> {
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { $0.needsTextRecognition && $0.textLinesData == nil }
    )
    descriptor.propertiesToFetch = [\.assetID]
    return try Set(self.modelContext.fetch(descriptor).map(\.assetID))
  }

  func gifticonExtractionPendingIDs() throws -> Set<ImageAsset.ID> {
    let rawValue = ImageCategory.gifticon.rawValue
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.textLinesData != nil && image.memberships.contains { $0.category == rawValue }
      }
    )
    descriptor.propertiesToFetch = [\.assetID, \.gifticonRulesVersion, \.gifticonExpiryDay]
    // 버전 비교를 조건에 넣지 않고 여기서 거르는 것은 만료일 해석 실패 판정(`storedGifticon`)을 조건으로 쓸 수 없어서다.
    // 후보는 기프티콘 읽음 행뿐이라 많지 않다.
    return try Set(
      self.modelContext.fetch(descriptor).filter { Self.storedGifticon($0) == nil }.map(\.assetID)
    )
  }

  func saveGifticons(_ gifticons: [ImageAsset.ID: GifticonInfo]) throws {
    try self.write {
      let ids = Array(gifticons.keys)
      let stored = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      let rawValue = ImageCategory.gifticon.rawValue
      for image in stored {
        // `gifticonExtractionPendingIDs` 와 같은 조건인 행만 바꾼다. 이미 지금 버전으로 추출한 행을 덮지 않아,
        // 겹친 지난 실행이 앞서 읽은 줄로 뽑은 값이 새 추출을 덮지 않고, 다시 대기가 된 행에 값이 붙지 않는다.
        guard image.textLinesData != nil,
              image.memberships.contains(where: { $0.category == rawValue }),
              Self.storedGifticon(image) == nil,
              let gifticon = gifticons[image.assetID]
        else {
          continue
        }
        Self.setGifticon(gifticon, on: image)
      }
    }
  }

  func images(ids: Set<ImageAsset.ID>) throws -> [IndexedImage] {
    let ids = Array(ids)
    let stored = try self.modelContext.fetch(
      FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
    )
    let decoder = PropertyListDecoder()
    return try stored.map { try Self.indexedImage($0, decoder: decoder) }
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

  /// 행을 읽지 않고 세므로 여행마다 든 사진 식별자 배열을 디코딩하지 않는다.
  func tripCount() throws -> Int {
    try self.modelContext.fetchCount(FetchDescriptor<StoredTrip>())
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

  /// 저장된 추출 값. nil 이면 추출하지 않은 것으로 본다(읽기·추출 대기·`saveGifticons` 가 모두 이 판정을 쓴다).
  /// 버전은 맞는데 만료일 정수를 날짜로 해석하지 못하면 던지지 않고 추출하지 않은 것으로 본다. 던지면 그 행이 든
  /// `images(in: .gifticon)` 이 계속 실패해 사용자가 회복할 수 없고, 추출 값은 저장된 줄로 다시 만들 수 있다
  /// (추출 대기에 들어 소급 추출이 다시 쓴다). 쓰는 쪽은 늘 유효한 날짜를 쓰므로 정상 흐름에서는 생기지 않는다.
  private static func storedGifticon(_ stored: StoredImage) -> GifticonInfo? {
    // `!=` 라 앱을 되돌려 더 높은 버전이 남아도 다시 추출한다.
    guard stored.gifticonRulesVersion == GifticonExtractor.rulesVersion else {
      return nil
    }
    let expiryDate: LocalDate?
    if let day = stored.gifticonExpiryDay {
      guard let date = Self.localDate(day) else {
        return nil
      }
      expiryDate = date
    } else {
      expiryDate = nil
    }
    return GifticonInfo(expiryDate: expiryDate, redemptionPlace: stored.gifticonRedemptionPlace)
  }

  /// 추출함이면 지금 규칙 버전과 값을, nil(추출 안 함)이면 (0, nil, nil) 을 쓴다.
  private static func setGifticon(_ gifticon: GifticonInfo?, on stored: StoredImage) {
    stored.gifticonRulesVersion = gifticon == nil ? 0 : GifticonExtractor.rulesVersion
    stored.gifticonExpiryDay = gifticon?.expiryDate.map { Self.dayNumber($0) }
    stored.gifticonRedemptionPlace = gifticon?.redemptionPlace
  }

  /// 저장 형식 yyyymmdd. 연도가 0 이상이면 `localDate` 와 왕복이 정확하다(추출기는 음수 연도를 내지 않는다).
  private static func dayNumber(_ date: LocalDate) -> Int {
    date.year * 10000 + date.month * 100 + date.day
  }

  private static func localDate(_ dayNumber: Int) -> LocalDate? {
    LocalDate(year: dayNumber / 10000, month: dayNumber / 100 % 100, day: dayNumber % 100)
  }

  /// `StoredImage.needsTextRecognition` 문서의 표대로 읽는다.
  private static func textRecognition(_ stored: StoredImage, decoder: PropertyListDecoder) throws -> TextRecognition {
    if let data = stored.textLinesData {
      return try .recognized(decoder.decode([RecognizedTextLine].self, from: data))
    }
    return stored.needsTextRecognition ? .pending : .notNeeded
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
      textRecognition: Self.textRecognition(stored, decoder: decoder),
      categories: Set(stored.memberships.compactMap { ImageCategory(rawValue: $0.category) }),
      gifticon: Self.storedGifticon(stored)
    )
  }
}

// 만료 알림용 조회 (docs/ARCHITECTURE.md §4 만료 알림).
extension PhotoStore {
  func upcomingGifticonExpiries(from date: LocalDate) throws -> [GifticonExpiry] {
    let version = GifticonExtractor.rulesVersion
    let from = Self.dayNumber(date)
    // 만료일 정수가 있는 행은 `setGifticon` 으로만 생기고 그 경로는 늘 기프티콘 읽음 행이라 카테고리 조건은 넣지 않는다.
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.gifticonRulesVersion == version && (image.gifticonExpiryDay.flatMap { $0 >= from } ?? false)
      },
      sortBy: [SortDescriptor(\.gifticonExpiryDay), SortDescriptor(\.assetID)]
    )
    descriptor.propertiesToFetch = [\.assetID, \.gifticonExpiryDay]
    return try self.modelContext.fetch(descriptor).compactMap { stored in
      // 날짜로 해석하지 못하는 정수는 `storedGifticon` 처럼 추출하지 않은 것으로 본다(추출 대기에 든다).
      guard let day = stored.gifticonExpiryDay, let expiryDate = Self.localDate(day) else {
        return nil
      }
      return GifticonExpiry(imageID: stored.assetID, expiryDate: expiryDate)
    }
  }
}
