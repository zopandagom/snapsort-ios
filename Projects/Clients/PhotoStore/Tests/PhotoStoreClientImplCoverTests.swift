import Core
import Foundation
import PhotoStoreInterface
import Testing
@testable import PhotoStoreImpl

struct PhotoStoreClientImplCoverTests {
  @Test("카테고리마다 최신 limit 장을 최신순으로 준다")
  func latestPerCategory() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "c1", creationDate: CoverFixture.date(100), categories: [.chat]),
      .stub(id: "c2", creationDate: CoverFixture.date(400), categories: [.chat]),
      .stub(id: "c3", creationDate: CoverFixture.date(300), categories: [.chat]),
      .stub(id: "c4", creationDate: CoverFixture.date(200), categories: [.chat]),
      .stub(id: "f1", creationDate: CoverFixture.date(50), categories: [.food]),
    ])

    let covers = try await store.categoryCovers(limit: 3)

    #expect(covers == [.chat: ["c2", "c3", "c4"], .food: ["f1"]])
  }

  @Test("생성일이 같으면 식별자 순(Swift 문자열 순)이고 limit 경계의 동률도 그 순서로 고른다")
  func tiesUseSwiftStringOrder() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let same = CoverFixture.date(100)
    // SwiftData 의 문자열 정렬이면 "9" < "10", "a" < "B" 라 결과가 달라진다.
    try await store.save(
      ["a", "B", "Z", "10", "9"].map { .stub(id: $0, creationDate: same, categories: [.chat]) }
        + [.stub(id: "new", creationDate: CoverFixture.date(200), categories: [.chat])]
    )

    #expect(try await store.categoryCovers(limit: 3) == [.chat: ["new", "10", "9"]])
    #expect(try await store.categoryCovers(limit: 5) == [.chat: ["new", "10", "9", "B", "Z"]])
    #expect(try await store.categoryCovers(limit: 6) == [.chat: ["new", "10", "9", "B", "Z", "a"]])
  }

  @Test("생성일 없는 이미지는 날짜 있는 이미지 뒤에, limit 이 남을 때만 들고 그 안은 식별자 순이다")
  func undatedComeLast() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "u2", creationDate: nil, categories: [.document]),
      .stub(id: "d2", creationDate: CoverFixture.date(100), categories: [.document]),
      .stub(id: "u3", creationDate: nil, categories: [.document]),
      .stub(id: "d1", creationDate: CoverFixture.date(200), categories: [.document]),
      .stub(id: "u1", creationDate: nil, categories: [.document]),
    ])

    #expect(try await store.categoryCovers(limit: 2) == [.document: ["d1", "d2"]])
    #expect(try await store.categoryCovers(limit: 4) == [.document: ["d1", "d2", "u1", "u2"]])
    #expect(try await store.categoryCovers(limit: 10) == [.document: ["d1", "d2", "u1", "u2", "u3"]])
  }

  @Test("한 이미지가 여러 카테고리면 각 카테고리에 든다")
  func imageInSeveralCategories() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "both", creationDate: CoverFixture.date(100), categories: [.receipt, .document]),
      .stub(id: "receipt", creationDate: CoverFixture.date(50), categories: [.receipt]),
    ])

    #expect(try await store.categoryCovers(limit: 4) == [.receipt: ["both", "receipt"], .document: ["both"]])
  }

  @Test("이미지가 없는 카테고리는 빠지고 limit 이 0 이면 빈 사전이다")
  func emptyCategoriesAndZeroLimit() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    #expect(try await store.categoryCovers(limit: 4).isEmpty)

    try await store.save([.stub(id: "a", creationDate: CoverFixture.date(100), categories: [.food])])
    try await store.replaceTrips([CoverFixture.trip(["a"], start: 0)])

    #expect(try await Set(store.categoryCovers(limit: 4).keys) == [.food, .travel])
    #expect(try await store.categoryCovers(limit: 0).isEmpty)
    #expect(try await store.categoryCovers(limit: -1).isEmpty)
  }

  @Test("카테고리마다 assets(in:) 의 앞 limit 장과 같다")
  func matchesAssetsPrefix() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save(CoverFixture.mixedImages)

    for limit in [1, 2, 4, 7] {
      let covers = try await store.categoryCovers(limit: limit)
      for category in ImageCategory.allCases where category != .travel {
        let expected = try await store.assets(in: category).prefix(limit).map(\.id)
        #expect((covers[category] ?? []) == expected, "\(category) limit \(limit)")
      }
    }
  }

  @Test("여행은 최근 여행부터 limit 개, 같은 시작이면 끝이 늦은 여행이 먼저다")
  func recentTripsFirst() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save(["old", "mid", "short", "long"].map { .stub(id: $0, categories: [.food]) })
    try await store.replaceTrips([
      CoverFixture.trip(["old"], start: 0),
      CoverFixture.trip(["short"], start: 1000, end: 1100),
      CoverFixture.trip(["mid"], start: 500),
      CoverFixture.trip(["long"], start: 1000, end: 1200),
    ])

    #expect(try await store.categoryCovers(limit: 3)[.travel] == ["long", "short", "mid"])
    #expect(try await store.categoryCovers(limit: 4)[.travel] == ["long", "short", "mid", "old"])
  }

  @Test("여행 대표는 가운데 → 첫 → 마지막 중 저장소에 있는 첫 장이다")
  func tripCoverCandidateOrder() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save(["a1", "a2", "a3", "b1", "b3", "c3"].map { .stub(id: $0, categories: [.food]) })
    try await store.replaceTrips([
      CoverFixture.trip(["a1", "a2", "a3"], start: 300),
      // 가운데(b2)가 지워져 첫 장.
      CoverFixture.trip(["b1", "b2", "b3"], start: 200),
      // 가운데·첫이 지워져 마지막 장.
      CoverFixture.trip(["c1", "c2", "c3"], start: 100),
    ])

    #expect(try await store.categoryCovers(limit: 4)[.travel] == ["a2", "b1", "c3"])
  }

  @Test("후보가 모두 저장소에 없거나 사진이 없는 여행은 건너뛰고 더 오래된 여행으로 채우지 않는다")
  func skipsTripsWithoutCover() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save(["new", "oldest"].map { .stub(id: $0, categories: [.food]) })
    try await store.replaceTrips([
      CoverFixture.trip(["new"], start: 400),
      CoverFixture.trip(["gone1", "gone2", "gone3"], start: 300),
      CoverFixture.trip([], start: 200),
      CoverFixture.trip(["oldest"], start: 100),
    ])

    #expect(try await store.categoryCovers(limit: 3)[.travel] == ["new"])
  }

  @Test("여행이 없으면 .travel 이 빠진다")
  func noTravelWithoutTrips() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([.stub(id: "a", creationDate: CoverFixture.date(100), categories: [.food])])
    #expect(try await store.categoryCovers(limit: 4)[.travel] == nil)

    try await store.replaceTrips([CoverFixture.trip(["gone"], start: 0)])
    #expect(try await store.categoryCovers(limit: 4)[.travel] == nil)
  }
}

/// 대표 조회 테스트(Impl·Fake)가 함께 쓰는 값.
enum CoverFixture {
  /// `seconds` 는 기준 시각부터 센 초.
  static func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_780_000_000 + seconds)
  }

  /// `end` 가 없으면 시작 한 시간 뒤에 끝난다.
  static func trip(_ ids: [String], start: TimeInterval, end: TimeInterval? = nil) -> Trip {
    Trip(
      assetIDs: ids,
      startDate: self.date(start),
      endDate: self.date(end ?? start + 3600),
      center: Coordinate(latitude: 33.5, longitude: 126.53)
    )
  }

  /// 생성일·동률·생성일 없음·여러 카테고리가 섞인 이미지.
  static let mixedImages: [IndexedImage] = [
    .stub(id: "a", creationDate: date(300), categories: [.chat, .shopping]),
    .stub(id: "B", creationDate: date(300), categories: [.chat]),
    .stub(id: "10", creationDate: date(300), categories: [.chat, .document]),
    .stub(id: "9", creationDate: date(300), categories: [.chat]),
    .stub(id: "x", creationDate: date(500), categories: [.chat, .food]),
    .stub(id: "u1", creationDate: nil, categories: [.chat, .shopping]),
    .stub(id: "U2", creationDate: nil, categories: [.shopping, .document]),
    .stub(id: "s1", creationDate: date(100), categories: [.shopping]),
    .stub(id: "d1", creationDate: date(700), categories: [.document]),
    .stub(id: "d2", creationDate: date(700), categories: [.document]),
  ]
}
