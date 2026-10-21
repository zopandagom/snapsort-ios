import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 여행 폴더: 식별자·기간 조회와 장소 캐시 (docs/ARCHITECTURE.md §4 저장소).
extension PhotoStore {
  /// 한 번의 `ids.contains` 조회에 넣는 식별자 수. 여행 사진은 수천 개일 수 있어 나눠 조회한다.
  static let idBatchSize = 1000

  /// 라벨·OCR 줄을 디코딩하지 않고 메타데이터 열만 읽는다.
  func assets(ids: [ImageAsset.ID]) throws -> [ImageAsset] {
    var seen: Set<ImageAsset.ID> = []
    let unique = ids.filter { seen.insert($0).inserted }
    var byID: [ImageAsset.ID: ImageAsset] = [:]
    for start in stride(from: 0, to: unique.count, by: Self.idBatchSize) {
      let batch = Array(unique[start ..< min(start + Self.idBatchSize, unique.count)])
      var descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { batch.contains($0.assetID) })
      descriptor.propertiesToFetch = [
        \.assetID, \.creationDate, \.latitude, \.longitude, \.pixelWidth, \.pixelHeight, \.isScreenshot,
      ]
      for stored in try self.modelContext.fetch(descriptor) {
        byID[stored.assetID] = Self.imageAsset(stored)
      }
    }
    return unique.compactMap { byID[$0] }
  }

  /// 생성일 [start, end) 와 카테고리를 조회 조건으로 거르고, 행의 카테고리로 묶어 `assets(in:)` 과 같은 순서로 정렬한다.
  func assets(
    in categories: Set<ImageCategory>,
    createdIn interval: DateInterval
  ) throws -> [ImageCategory: [ImageAsset]] {
    let requested = categories.subtracting([.travel])
    let rawValues = requested.map(\.rawValue)
    guard !rawValues.isEmpty else {
      return [:]
    }
    let start = interval.start
    let end = interval.end
    let stored = try self.modelContext.fetch(
      FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          (image.creationDate.flatMap { $0 >= start && $0 < end } ?? false)
            && image.memberships.contains { rawValues.contains($0.category) }
        }
      )
    )
    var grouped: [ImageCategory: [StoredImage]] = [:]
    for image in stored {
      for membership in image.memberships {
        if let category = ImageCategory(rawValue: membership.category), requested.contains(category) {
          grouped[category, default: []].append(image)
        }
      }
    }
    return grouped.mapValues { $0.sorted(by: Self.isNewer).map(Self.imageAsset) }
  }

  /// 캐시는 여행 수만큼만 있는 작은 표라 전부 읽고 여기서 거른다.
  func places(for keys: Set<RoundedCoordinate>, localeIdentifier: String) throws -> [RoundedCoordinate: CachedPlace] {
    guard !keys.isEmpty else {
      return [:]
    }
    var result: [RoundedCoordinate: CachedPlace] = [:]
    for place in try self.modelContext.fetch(FetchDescriptor<StoredPlaceName>()) {
      guard let key = Self.placeKey(place), keys.contains(key) else {
        continue
      }
      let name: CachedPlaceName? = if place.localeIdentifier == localeIdentifier {
        place.name.map(CachedPlaceName.named) ?? .unnamed
      } else {
        nil
      }
      result[key] = CachedPlace(name: name, timeZoneIdentifier: place.timeZoneIdentifier)
    }
    return result
  }

  /// 여행 키를 확인한 뒤 키의 행을 덮거나 새로 넣는다. unique 제약 없이 이 actor 안에서 조회 후 갱신하므로,
  /// 같은 키 행이 여럿이면 하나만 남긴다.
  func savePlace(
    _ name: CachedPlaceName,
    timeZoneIdentifier: String?,
    for key: RoundedCoordinate,
    localeIdentifier: String
  ) throws -> Bool {
    var saved = false
    try self.write {
      var tripDescriptor = FetchDescriptor<StoredTrip>()
      tripDescriptor.propertiesToFetch = [\.centerLatitude, \.centerLongitude]
      let hasTrip = try self.modelContext.fetch(tripDescriptor).contains { trip in
        RoundedCoordinate(Coordinate(latitude: trip.centerLatitude, longitude: trip.centerLongitude)) == key
      }
      guard hasTrip else {
        return
      }
      let latitude = key.latitudeHundredths
      let longitude = key.longitudeHundredths
      let existing = try self.modelContext.fetch(
        FetchDescriptor<StoredPlaceName>(
          predicate: #Predicate { $0.latitudeHundredths == latitude && $0.longitudeHundredths == longitude }
        )
      )
      for extra in existing.dropFirst() {
        self.modelContext.delete(extra)
      }
      let storedName: String? = if case let .named(value) = name {
        value
      } else {
        nil
      }
      if let place = existing.first {
        place.localeIdentifier = localeIdentifier
        place.name = storedName
        place.timeZoneIdentifier = timeZoneIdentifier
      } else {
        self.modelContext.insert(
          StoredPlaceName(
            latitudeHundredths: latitude,
            longitudeHundredths: longitude,
            localeIdentifier: localeIdentifier,
            name: storedName,
            timeZoneIdentifier: timeZoneIdentifier
          )
        )
      }
      saved = true
    }
    return saved
  }

  /// 새 여행 어디의 중심점 키도 아닌 장소 캐시를 지운다(여행이 사라지면 그 이름도 남기지 않는다).
  /// `replaceTrips` 가 같은 `write` 안에서 부른다. 저장은 부르는 쪽이 한다.
  func deletePlaces(notIn trips: [Trip]) throws {
    let keys = Set(trips.compactMap(\.placeKey))
    for place in try self.modelContext.fetch(FetchDescriptor<StoredPlaceName>()) {
      if let key = Self.placeKey(place), keys.contains(key) {
        continue
      }
      self.modelContext.delete(place)
    }
  }

  /// 캐시 행의 키. 저장된 정수가 범위 밖이면 nil (`replaceTrips` 가 지운다).
  static func placeKey(_ place: StoredPlaceName) -> RoundedCoordinate? {
    RoundedCoordinate(latitudeHundredths: place.latitudeHundredths, longitudeHundredths: place.longitudeHundredths)
  }
}
