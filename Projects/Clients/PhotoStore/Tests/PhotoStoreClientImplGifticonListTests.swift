import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// Impl 만의 기프티콘 목록 동작: 경량 이전, 출처를 모르는 마침을 넘긴 저장. 같은 동작은 `PhotoStoreGifticonListTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplGifticonListTests {
  @Test("사용 여부·출처 속성 전 저장 파일이 열리고, 보강 마침 행은 값 그대로 출처를 모르는 마침으로 읽힌다")
  func migratesStoreSavedBeforeGifticonScreen() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writePreGifticonScreenRows(at: url)

    let store = try PhotoStoreClientImpl(url: url)

    let images = try await Dictionary(
      uniqueKeysWithValues: store.images(ids: ["done", "pending", "stale"]).map { ($0.id, $0) }
    )
    #expect(images.mapValues(\.gifticonModelFill) == [
      "done": .sourcesUnknown,
      "pending": .pending(failures: 2),
      "stale": .stale,
    ])
    #expect(images.values.allSatisfy { $0.gifticon == GifticonListFixture.complete })
    #expect(try await store.gifticonModelFillPendingIDs() == ["done", "pending", "stale"])
    // 값을 되돌리지 않으므로 알림도 그대로다.
    #expect(try await store.upcomingGifticonExpiries(from: GifticonListFixture.date(2026, 1, 1)).map(\.imageID)
      == ["done", "pending", "stale"])
    let items = try await store.gifticons()
    #expect(items.allSatisfy { !$0.isUsed })
    #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.estimatedFields) }) == [
      "done": [.expiryDate, .redemptionPlace],
      "pending": [],
      "stale": [.expiryDate, .redemptionPlace],
    ])
  }

  @Test("출처를 모르는 마침을 넘겨 저장하면 다른 보강 버전처럼 보강하지 않음으로 쓴다")
  func savesSourcesUnknownAsUnfilled() async throws {
    let store = try PhotoStoreClientImpl.inMemory()

    try await store.save([GifticonListFixture.gifticon("a", info: GifticonListFixture.complete, fill: .sourcesUnknown)])

    let image = try #require(try await store.images(ids: ["a"]).first)
    #expect(image.gifticonModelFill == .pending(failures: 0))
    #expect(image.gifticon == GifticonListFixture.complete)
  }

  /// 이전 빌드처럼 사용 여부·출처 열이 없는 스키마로 기프티콘 읽음 행 셋(보강 마침·대기·다른 보강 버전)을 쓰고 컨테이너를 놓는다.
  private static func writePreGifticonScreenRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreGifticonScreenSchema.StoredImage.self,
      PreGifticonScreenSchema.StoredCategoryMembership.self,
      PreGifticonScreenSchema.StoredTrip.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    let modelVersions = [
      "done": GifticonExtractor.modelFillVersion,
      "pending": 0,
      "stale": GifticonExtractor.modelFillVersion + 1,
    ]
    for (id, modelVersion) in modelVersions {
      let stored = PreGifticonScreenSchema.StoredImage(assetID: id)
      stored.labelsData = try encoder.encode([ImageLabel]())
      stored.needsTextRecognition = true
      stored.textLinesData = try encoder.encode(GifticonListFixture.lines)
      stored.gifticonRulesVersion = GifticonExtractor.rulesVersion
      stored.gifticonExpiryDay = 20_261_231
      stored.gifticonRedemptionPlace = "스타벅스"
      stored.gifticonModelVersion = modelVersion
      stored.gifticonModelFailures = id == "pending" ? 2 : 0
      context.insert(stored)
      let membership = PreGifticonScreenSchema.StoredCategoryMembership(category: ImageCategory.gifticon.rawValue)
      stored.memberships = [membership]
    }
    try context.save()
  }
}
