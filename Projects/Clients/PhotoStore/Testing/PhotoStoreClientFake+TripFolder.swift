import Core
import Foundation
import PhotoStoreInterface

// 여행·여행 폴더: 여행 교체·읽기, 식별자·기간 조회와 장소 캐시 (docs/ARCHITECTURE.md §4 저장소).
public extension PhotoStoreClientFake {
  /// `trips()` 를 부른 횟수. `tripsErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var tripsCallCount: Int {
    self.state.withLock { $0.tripFolder.tripsCallCount }
  }

  /// `places(for:localeIdentifier:)` 를 부른 횟수. 실패한 호출도 센다.
  var placesCallCount: Int {
    self.state.withLock { $0.tripFolder.placesCallCount }
  }

  /// `savePlace` 로 캐시에 쓴 것을 부른 순서대로. 실패하거나 여행이 없어 false 를 돌려준 호출은 빠진다.
  var savedPlaces: [SavedPlace] {
    self.state.withLock { $0.tripFolder.savedPlaces }
  }

  /// Impl 처럼 새 여행의 중심점 키에 해당하지 않는 장소 캐시를 지운다.
  func replaceTrips(_ trips: [Trip]) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    let keys = Set(trips.compactMap(\.placeKey))
    self.state.withLock { state in
      state.trips = trips
      state.tripFolder.places = state.tripFolder.places.filter { keys.contains($0.key) }
      state.replaceTripsCount += 1
    }
  }

  /// Impl 처럼 시작 시각 순(같으면 끝 시각 순)으로 돌려준다.
  func trips() async throws(PhotoStoreError) -> [Trip] {
    try self.throwIfNeeded()
    let (index, trips) = self.state.withLock { state in
      defer { state.tripFolder.tripsCallCount += 1 }
      return (state.tripFolder.tripsCallCount, state.trips)
    }
    if let error = self.tripFolderOptions.tripsErrors[index] {
      throw error
    }
    let sorted = trips.sorted { ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate) }
    await self.tripFolderOptions.onTrips(index)
    return sorted
  }

  func tripCount() async throws(PhotoStoreError) -> Int {
    try self.throwIfNeeded()
    return self.state.withLock { $0.trips.count }
  }

  /// 프로토콜 약속대로 넘긴 순서(중복은 처음 것만)로 돌려주고 없는 식별자는 뺀다.
  func assets(ids: [ImageAsset.ID]) async throws(PhotoStoreError) -> [ImageAsset] {
    try self.throwIfNeeded()
    let (index, assets) = self.state.withLock { state in
      defer { state.tripFolder.tripAssetsCallCount += 1 }
      var seen: Set<ImageAsset.ID> = []
      let assets = ids.compactMap { id in seen.insert(id).inserted ? state.images[id]?.asset : nil }
      return (state.tripFolder.tripAssetsCallCount, assets)
    }
    if let error = self.tripFolderOptions.tripAssetsErrors[index] {
      throw error
    }
    await self.tripFolderOptions.onTripAssets(index)
    return assets
  }

  /// 프로토콜 약속대로 [start, end) 에 생성된 이미지를 카테고리별 최신순으로 돌려준다. `.travel`·빈 카테고리는 뺀다.
  func assets(
    in categories: Set<ImageCategory>,
    createdIn interval: DateInterval
  ) async throws(PhotoStoreError) -> [ImageCategory: [ImageAsset]] {
    try self.throwIfNeeded()
    let (index, images) = self.state.withLock { state in
      defer { state.tripFolder.periodAssetsCallCount += 1 }
      return (state.tripFolder.periodAssetsCallCount, Array(state.images.values))
    }
    if let error = self.tripFolderOptions.periodAssetsErrors[index] {
      throw error
    }
    let inPeriod = images.filter { image in
      image.asset.creationDate.map { interval.start <= $0 && $0 < interval.end } ?? false
    }
    var result: [ImageCategory: [ImageAsset]] = [:]
    for category in categories.subtracting([.travel]) {
      let assets = inPeriod.filter { $0.categories.contains(category) }.sorted(by: Self.isNewer).map(\.asset)
      if !assets.isEmpty {
        result[category] = assets
      }
    }
    await self.tripFolderOptions.onPeriodAssets(index)
    return result
  }

  /// Impl 처럼 이름은 같은 locale 일 때만, 시간대는 locale 과 무관하게 돌려준다.
  func places(
    for keys: Set<RoundedCoordinate>,
    localeIdentifier: String
  ) async throws(PhotoStoreError) -> [RoundedCoordinate: CachedPlace] {
    self.state.withLock { $0.tripFolder.placesCallCount += 1 }
    try self.throwIfNeeded()
    if let error = self.tripFolderOptions.placeError {
      throw error
    }
    return self.state.withLock { state in
      state.tripFolder.places.filter { keys.contains($0.key) }.mapValues { place in
        CachedPlace(
          name: place.localeIdentifier == localeIdentifier ? place.name : nil,
          timeZoneIdentifier: place.timeZoneIdentifier
        )
      }
    }
  }

  /// Impl 처럼 중심점 키가 key 인 여행이 있을 때만 쓰고(같은 키는 덮는다) true, 없으면 false.
  func savePlace(
    _ name: CachedPlaceName,
    timeZoneIdentifier: String?,
    for key: RoundedCoordinate,
    localeIdentifier: String
  ) async throws(PhotoStoreError) -> Bool {
    try self.throwIfNeeded()
    if let error = self.tripFolderOptions.placeError {
      throw error
    }
    return self.state.withLock { state in
      guard state.trips.contains(where: { $0.placeKey == key }) else {
        return false
      }
      state.tripFolder.places[key] = StoredPlace(
        localeIdentifier: localeIdentifier,
        name: name,
        timeZoneIdentifier: timeZoneIdentifier
      )
      state.tripFolder.savedPlaces.append(
        SavedPlace(key: key, localeIdentifier: localeIdentifier, name: name, timeZoneIdentifier: timeZoneIdentifier)
      )
      return true
    }
  }
}

extension PhotoStoreClientFake {
  /// 여행 폴더용 실패·훅. init 매개변수 문서대로다.
  struct TripFolderOptions {
    let tripsErrors: [Int: PhotoStoreError]
    let onTrips: @Sendable (Int) async -> Void
    let tripAssetsErrors: [Int: PhotoStoreError]
    let onTripAssets: @Sendable (Int) async -> Void
    let periodAssetsErrors: [Int: PhotoStoreError]
    let onPeriodAssets: @Sendable (Int) async -> Void
    let placeError: PhotoStoreError?
  }

  /// 여행 폴더용 저장 상태와 기록.
  struct TripFolderState {
    var places: [RoundedCoordinate: StoredPlace] = [:]
    var tripsCallCount = 0
    var tripAssetsCallCount = 0
    var periodAssetsCallCount = 0
    var placesCallCount = 0
    var savedPlaces: [SavedPlace] = []
  }

  /// 키 하나의 장소 캐시. `name` 이 nil 이면 어느 locale 로도 이름이 없다(시드에서 시간대만 둔 경우).
  struct StoredPlace {
    var localeIdentifier: String
    var name: CachedPlaceName?
    var timeZoneIdentifier: String?
  }

  /// 시드 장소를 그 locale 로 캐시한 것으로 바꾼다.
  static func storedPlaces(
    _ places: [RoundedCoordinate: CachedPlace],
    localeIdentifier: String
  ) -> [RoundedCoordinate: StoredPlace] {
    places.mapValues { place in
      StoredPlace(localeIdentifier: localeIdentifier, name: place.name, timeZoneIdentifier: place.timeZoneIdentifier)
    }
  }
}

/// `PhotoStoreClientFake.savePlace` 로 캐시에 쓴 것 하나.
public struct SavedPlace: Sendable, Equatable {
  public let key: RoundedCoordinate
  public let localeIdentifier: String
  public let name: CachedPlaceName
  public let timeZoneIdentifier: String?

  public init(key: RoundedCoordinate, localeIdentifier: String, name: CachedPlaceName, timeZoneIdentifier: String?) {
    self.key = key
    self.localeIdentifier = localeIdentifier
    self.name = name
    self.timeZoneIdentifier = timeZoneIdentifier
  }
}
