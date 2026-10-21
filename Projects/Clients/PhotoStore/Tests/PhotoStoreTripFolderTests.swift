import Core
import Foundation
import PhotoStoreInterface
import Testing

/// 여행 폴더용 조회·장소 캐시. Impl 과 Fake 가 같은 동작인지 같은 테스트로 본다. 장소 이름은 지어낸 값이다.
struct PhotoStoreTripFolderTests {
  @Test("식별자 조회는 넘긴 순서로, 중복은 처음 것만, 없는 식별자는 빼고 돌려준다", arguments: StoreKind.allCases)
  func readsAssetsByIDsInOrder(kind: StoreKind) async throws {
    let store = try await kind.make([Self.image("a", at: 10), Self.image("b", at: 20), Self.image("c", at: 30)])
    defer { store.remove() }

    let assets = try await store.client.assets(ids: ["c", "missing", "a", "c", "b"])

    #expect(assets.map(\.id) == ["c", "a", "b"])
    #expect(assets.first?.creationDate == Self.date(30))
    #expect(try await store.client.assets(ids: []).isEmpty)
  }

  @Test("식별자 2,500개도 나눠 조회해 모두 순서대로 돌려준다", arguments: StoreKind.allCases)
  func readsManyAssetsByIDs(kind: StoreKind) async throws {
    let ids = (0 ..< 2500).map { String(format: "p%04d", $0) }
    let store = try await kind.make(ids.map { Self.image($0, at: 0) })
    defer { store.remove() }

    let assets = try await store.client.assets(ids: ids.reversed())

    #expect(assets.map(\.id) == ids.reversed())
  }

  @Test("기간 조회는 시작을 포함하고 끝을 빼며, 날짜 없는 이미지·다른 카테고리는 뺀다", arguments: StoreKind.allCases)
  func readsAssetsInHalfOpenInterval(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.image("before", at: 99, categories: [.receipt]),
      Self.image("start", at: 100, categories: [.receipt]),
      Self.image("middle", at: 150, categories: [.receipt]),
      Self.image("end", at: 200, categories: [.receipt]),
      Self.image("noDate", at: nil, categories: [.receipt]),
      Self.image("food", at: 150, categories: [.food]),
    ])
    defer { store.remove() }

    let assets = try await store.client.assets(in: [.receipt], createdIn: Self.interval(100, 200))

    #expect(assets.mapValues { $0.map(\.id) } == [.receipt: ["middle", "start"]])
  }

  @Test("두 카테고리에 든 이미지는 양쪽에 들고, 카테고리별 최신순이며 빈 카테고리는 빠진다", arguments: StoreKind.allCases)
  func groupsAssetsByCategory(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.image("both", at: 120, categories: [.receipt, .document]),
      Self.image("receipt", at: 150, categories: [.receipt]),
      Self.image("map", at: 110, categories: [.map]),
    ])
    defer { store.remove() }

    let assets = try await store.client.assets(in: [.receipt, .map, .document], createdIn: Self.interval(100, 200))

    #expect(assets.mapValues { $0.map(\.id) } == [
      .receipt: ["receipt", "both"],
      .document: ["both"],
      .map: ["map"],
    ])
    #expect(try await store.client.assets(in: [.chat], createdIn: Self.interval(100, 200)).isEmpty)
  }

  @Test("여행은 이미지 카테고리가 아니라 기간 조회에서 빠지고, 카테고리가 없으면 빈 결과다", arguments: StoreKind.allCases)
  func excludesTravelFromPeriodAssets(kind: StoreKind) async throws {
    let store = try await kind.make([Self.image("trip", at: 150, categories: [.travel, .receipt])])
    defer { store.remove() }

    #expect(try await store.client.assets(in: [.travel], createdIn: Self.interval(100, 200)).isEmpty)
    #expect(try await store.client.assets(in: [], createdIn: Self.interval(100, 200)).isEmpty)
    #expect(try await store.client.assets(in: [.travel, .receipt], createdIn: Self.interval(100, 200))
      .mapValues { $0.map(\.id) } == [.receipt: ["trip"]])
  }

  @Test("장소 캐시는 이름·시간대를 왕복하고, 캐시 없는 키는 결과에 없다", arguments: StoreKind.allCases)
  func roundTripsPlaces(kind: StoreKind) async throws {
    let store = try await kind.make([], trips: [Self.jejuTrip, Self.tokyoTrip])
    defer { store.remove() }

    #expect(try await store.client.savePlace(
      .named("제주시"), timeZoneIdentifier: "Asia/Seoul", for: Self.jeju, localeIdentifier: "ko_KR"
    ))
    #expect(try await store.client.savePlace(
      .unnamed,
      timeZoneIdentifier: nil,
      for: Self.tokyo,
      localeIdentifier: "ko_KR"
    ))

    let places = try await store.client.places(for: [Self.jeju, Self.tokyo, Self.ocean], localeIdentifier: "ko_KR")
    #expect(places == [
      Self.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul"),
      Self.tokyo: CachedPlace(name: .unnamed, timeZoneIdentifier: nil),
    ])
    #expect(try await store.client.places(for: [], localeIdentifier: "ko_KR").isEmpty)
  }

  @Test("locale 이 다르면 이름은 없고 시간대는 그대로다", arguments: StoreKind.allCases)
  func otherLocaleKeepsTimeZoneOnly(kind: StoreKind) async throws {
    let store = try await kind.make([], trips: [Self.jejuTrip])
    defer { store.remove() }
    _ = try await store.client.savePlace(
      .named("제주시"), timeZoneIdentifier: "Asia/Seoul", for: Self.jeju, localeIdentifier: "ko_KR"
    )

    let places = try await store.client.places(for: [Self.jeju], localeIdentifier: "en_US")

    #expect(places == [Self.jeju: CachedPlace(name: nil, timeZoneIdentifier: "Asia/Seoul")])
  }

  @Test("같은 키는 locale·이름·시간대를 모두 덮는다", arguments: StoreKind.allCases)
  func overwritesSameKey(kind: StoreKind) async throws {
    let store = try await kind.make([], trips: [Self.jejuTrip])
    defer { store.remove() }
    _ = try await store.client.savePlace(
      .named("제주시"), timeZoneIdentifier: "Asia/Seoul", for: Self.jeju, localeIdentifier: "ko_KR"
    )

    #expect(try await store.client.savePlace(
      .named("Jeju-si"), timeZoneIdentifier: nil, for: Self.jeju, localeIdentifier: "en_US"
    ))

    #expect(try await store.client.places(for: [Self.jeju], localeIdentifier: "en_US")
      == [Self.jeju: CachedPlace(name: .named("Jeju-si"), timeZoneIdentifier: nil)])
    #expect(try await store.client.places(for: [Self.jeju], localeIdentifier: "ko_KR")
      == [Self.jeju: CachedPlace(name: nil, timeZoneIdentifier: nil)])
  }

  @Test("중심점 키가 같은 여행이 없으면 쓰지 않고 false 이며 캐시가 남지 않는다", arguments: StoreKind.allCases)
  func refusesKeyWithoutTrip(kind: StoreKind) async throws {
    let store = try await kind.make([], trips: [Self.jejuTrip])
    defer { store.remove() }

    #expect(try await store.client.savePlace(
      .named("도쿄"), timeZoneIdentifier: "Asia/Tokyo", for: Self.tokyo, localeIdentifier: "ko_KR"
    ) == false)

    #expect(try await store.client.places(for: [Self.tokyo], localeIdentifier: "ko_KR").isEmpty)
  }

  @Test("여행을 바꾸면 새 여행 중심점 키가 아닌 캐시를 지우고, 같은 반올림 키는 둔다", arguments: StoreKind.allCases)
  func replaceTripsCleansPlaces(kind: StoreKind) async throws {
    let store = try await kind.make([], trips: [Self.jejuTrip, Self.tokyoTrip])
    defer { store.remove() }
    _ = try await store.client.savePlace(
      .named("제주시"), timeZoneIdentifier: "Asia/Seoul", for: Self.jeju, localeIdentifier: "ko_KR"
    )
    _ = try await store.client.savePlace(
      .named("도쿄"), timeZoneIdentifier: "Asia/Tokyo", for: Self.tokyo, localeIdentifier: "ko_KR"
    )
    // 사진이 늘어 중심점이 조금 움직였지만 반올림하면 같은 키인 제주 여행.
    let movedJeju = Self.trip(["j", "k"], center: Coordinate(latitude: 33.5031, longitude: 126.5284))
    #expect(movedJeju.placeKey == Self.jeju)

    try await store.client.replaceTrips([movedJeju])

    #expect(try await store.client.places(for: [Self.jeju, Self.tokyo], localeIdentifier: "ko_KR")
      == [Self.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul")])
    try await store.client.replaceTrips([Self.tokyoTrip])
    #expect(try await store.client.places(for: [Self.jeju, Self.tokyo], localeIdentifier: "ko_KR").isEmpty)
  }

  // MARK: 도우미

  static let jeju = RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653)!
  static let tokyo = RoundedCoordinate(latitudeHundredths: 3568, longitudeHundredths: 13976)!
  static let ocean = RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: -15000)!
  static let jejuTrip = Self.trip(["j"], center: Coordinate(latitude: 33.4996, longitude: 126.5312))
  static let tokyoTrip = Self.trip(["t"], center: Coordinate(latitude: 35.6812, longitude: 139.7621))

  static func trip(_ ids: [String], center: Coordinate) -> Trip {
    Trip(assetIDs: ids, startDate: self.date(0), endDate: self.date(3600), center: center)
  }

  /// `seconds` 는 기준 시각부터 센 초.
  static func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_780_000_000 + seconds)
  }

  static func interval(_ start: TimeInterval, _ end: TimeInterval) -> DateInterval {
    DateInterval(start: self.date(start), end: self.date(end))
  }

  static func image(
    _ id: String,
    at seconds: TimeInterval?,
    categories: Set<ImageCategory> = [.people]
  ) -> IndexedImage {
    .stub(id: id, creationDate: seconds.map(self.date), categories: categories)
  }
}
