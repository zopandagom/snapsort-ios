import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// Impl 만의 특징 벡터 동작: 버전, 해석 불가 행, 벡터 행 함께 지우기, 경량 이전. 같은 동작은 `PhotoStoreSimilarPhotoTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplSimilarPhotoTests {
  private typealias Fixture = SimilarPhotoStoreFixture

  @Test("다른 버전 벡터는 대기이고, 버전은 맞는데 데이터가 없거나 풀리지 않는 행은 던지지 않고 빠진다")
  func unreadableRows() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let valid = Fixture.featurePrint(0).floatData
    let rows = [
      RawRow(id: "oldVersion", version: ImageFeaturePrint.version - 256, data: valid),
      RawRow(id: "newerVersion", version: ImageFeaturePrint.version + 1, data: valid),
      RawRow(id: "current1", version: ImageFeaturePrint.version, data: valid),
      RawRow(id: "current2", version: ImageFeaturePrint.version, data: valid),
      RawRow(id: "corrupt", version: ImageFeaturePrint.version, data: valid.dropLast()),
      RawRow(id: "missingData", version: ImageFeaturePrint.version, data: nil),
    ]
    try Self.writeRows(at: url) { context, encoder in
      for (index, row) in rows.enumerated() {
        let stored = try Self.photoRow(row.id, seconds: TimeInterval(index), encoder: encoder, in: context)
        stored.featurePrintVersion = row.version
        if let data = row.data {
          let featurePrintRow = StoredFeaturePrint(assetID: row.id, data: data)
          context.insert(featurePrintRow)
          stored.featurePrint = featurePrintRow
        }
      }
    }
    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.featurePrintPendingIDs() == ["oldVersion", "newerVersion"])
    let entries = try await store.similarPhotoEntries()
    #expect(entries.photos.map(\.id) == ["current1", "current2"])
    #expect(entries.uncomparedCount == 2)
    let images = try await store.images(ids: Set(rows.map(\.id)))
    #expect(Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0.featurePrint != nil) }) == [
      "oldVersion": false, "newerVersion": false, "current1": true, "current2": true,
      "corrupt": false, "missingData": false,
    ])

    // 다른 버전 행은 소급 저장으로 지금 버전이 된다(관계 행을 새로 만들지 않고 데이터만 바꾼다).
    try await store.saveFeaturePrints(["oldVersion": Fixture.featurePrint(0.1)])
    #expect(try await store.images(ids: ["oldVersion"]).first?.featurePrint == Fixture.featurePrint(0.1))
    #expect(try Self.featurePrintRowCount(at: url) == 5)
  }

  @Test("이미지를 지우면 벡터 행도 함께 지워진다")
  func deleteCascades() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try PhotoStoreClientImpl(url: url)
    try await store.save([Fixture.photo("a", seconds: 0), Fixture.photo("b", seconds: 1)])
    #expect(try Self.featurePrintRowCount(at: url) == 2)

    try await store.delete(ids: ["a"])

    #expect(try Self.featurePrintRowCount(at: url) == 1)
  }

  @Test("벡터 속성 전 저장 파일이 경량 이전으로 열리고 대상 사진은 대기, 다른 값은 그대로다")
  func migratesStoreSavedBeforeFeaturePrints() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writePreSimilarPhotoRows(at: url)

    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.indexedIDs() == ["photo1", "photo2", "shot", "gifticon"])
    #expect(try await store.featurePrintPendingIDs() == ["photo1", "photo2"])
    let before = try await store.similarPhotoEntries()
    #expect(before.photos.isEmpty)
    #expect(before.uncomparedCount == 2)
    #expect(try await store.images(ids: ["gifticon"]).first?.gifticon == GifticonListFixture.complete)
    #expect(try await store.categoryCounts() == [.food: 2, .gifticon: 1, .other: 1])

    try await store.saveFeaturePrints(["photo1": Fixture.featurePrint(0), "photo2": Fixture.featurePrint(0.1)])

    let after = try await store.similarPhotoEntries()
    #expect(after.photos.map(\.id) == ["photo1", "photo2"])
    #expect(after.uncomparedCount == 0)
  }

  @Test("캐시로 다시 읽으면 처음 푼 벡터 버퍼를 그대로 줘 화면과 저장소가 한 벌을 함께 쓴다")
  func cachedReadSharesBuffers() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([Fixture.photo("a", seconds: 0, x: 0.1), Fixture.photo("b", seconds: 1, x: 0.2)])

    let first = try await store.similarPhotoEntries()
    let second = try await store.similarPhotoEntries()

    #expect(second == first)
    let address: (SimilarPhotoEntries) -> [UnsafeRawPointer?] = { entries in
      entries.photos.map { $0.featurePrint.values.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) } }
    }
    #expect(address(second) == address(first))
  }

  /// 버전·데이터를 직접 쓴 사진 행.
  private struct RawRow {
    let id: String
    let version: Int
    let data: Data?
  }

  /// 저장소가 쓰지 않는 값을 직접 넣기 위해 Impl 스키마로 파일을 만들고 컨테이너를 놓는다.
  private static func writeRows(
    at url: URL,
    _ write: (ModelContext, PropertyListEncoder) throws -> Void
  ) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
      StoredFeaturePrint.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    try write(context, PropertyListEncoder())
    try context.save()
  }

  private static func featurePrintRowCount(at url: URL) throws -> Int {
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
      StoredFeaturePrint.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    return try ModelContext(container).fetchCount(FetchDescriptor<StoredFeaturePrint>())
  }

  private static func photoRow(
    _ id: String,
    seconds: TimeInterval,
    encoder: PropertyListEncoder,
    in context: ModelContext
  ) throws -> StoredImage {
    let stored = StoredImage(assetID: id)
    stored.creationDate = Fixture.baseDate.addingTimeInterval(seconds)
    stored.labelsData = try encoder.encode([ImageLabel]())
    context.insert(stored)
    stored.memberships = [StoredCategoryMembership(category: ImageCategory.food.rawValue)]
    return stored
  }

  /// 이전 빌드처럼 벡터 속성이 없는 스키마로 카메라 사진 두 장·스크린샷·기프티콘 추출 행을 쓰고 컨테이너를 놓는다.
  private static func writePreSimilarPhotoRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreSimilarPhotoSchema.StoredImage.self,
      PreSimilarPhotoSchema.StoredCategoryMembership.self,
      PreSimilarPhotoSchema.StoredTrip.self,
      PreSimilarPhotoSchema.StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    let rows: [(id: String, category: ImageCategory)] = [
      ("photo1", .food), ("photo2", .food), ("shot", .other), ("gifticon", .gifticon),
    ]
    for (index, row) in rows.enumerated() {
      let image = PreSimilarPhotoSchema.StoredImage(assetID: row.id)
      image.creationDate = Fixture.baseDate.addingTimeInterval(TimeInterval(index))
      image.pixelWidth = 4032
      image.pixelHeight = 3024
      image.isScreenshot = row.category != .food
      image.labelsData = try encoder.encode([ImageLabel]())
      if row.category == .gifticon {
        image.needsTextRecognition = true
        image.textLinesData = try encoder.encode(GifticonListFixture.lines)
        image.gifticonRulesVersion = GifticonExtractor.rulesVersion
        image.gifticonExpiryDay = 20_261_231
        image.gifticonRedemptionPlace = "스타벅스"
        image.gifticonModelVersion = GifticonExtractor.modelFillVersion
        image.gifticonExpiryFromModel = false
        image.gifticonRedemptionPlaceFromModel = false
      } else if image.isScreenshot {
        image.needsTextRecognition = true
      }
      context.insert(image)
      image.memberships = [PreSimilarPhotoSchema.StoredCategoryMembership(category: row.category.rawValue)]
    }
    try context.save()
  }
}
