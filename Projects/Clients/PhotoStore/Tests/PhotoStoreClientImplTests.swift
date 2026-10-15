import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

struct PhotoStoreClientImplTests {
  @Test("저장한 이미지를 같은 값으로 다시 읽는다")
  func roundTripsImage() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let image = IndexedImage(
      asset: ImageAsset(
        id: "gifticon",
        creationDate: Date(timeIntervalSince1970: 1_700_000_000),
        coordinate: Coordinate(latitude: 37.5665, longitude: 126.978),
        pixelWidth: 1170,
        pixelHeight: 2532,
        isScreenshot: true
      ),
      labels: [ImageLabel(identifier: "document", confidence: 0.42)],
      textRecognition: .recognized([RecognizedTextLine(
        text: "유효기간 2026.12.31",
        confidence: 0.9,
        boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05)
      )]),
      categories: [.gifticon, .document]
    )

    try await store.save([image])

    #expect(try await store.images(in: .gifticon) == [image])
    #expect(try await store.indexedIDs() == ["gifticon"])
  }

  @Test("OCR 대상 아님·대기·글자 없이 읽음을 구분해 같은 값으로 다시 읽는다")
  func keepsTextRecognitionStates() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let images: [IndexedImage] = [
      .stub(id: "photo", textRecognition: .notNeeded, categories: [.food]),
      .stub(id: "pending", textRecognition: .pending, categories: [.food]),
      .stub(id: "blank", textRecognition: .recognized([]), categories: [.food]),
    ]

    try await store.save(images)

    let stored = try await store.images(in: .food)
    #expect(Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.textRecognition) }) == [
      "photo": .notNeeded, "pending": .pending, "blank": .recognized([]),
    ])
    #expect(stored.first { $0.id == "pending" }?.textLines == nil)
    #expect(stored.first { $0.id == "blank" }?.textLines == [])
  }

  @Test("OCR 대기 식별자는 대기만 돌려주고, 읽음으로 다시 저장하면 빠진다")
  func listsPendingTextRecognition() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "photo"),
      .stub(id: "a", textRecognition: .pending),
      .stub(id: "b", textRecognition: .pending),
      .stub(id: "read", textRecognition: .recognized([])),
    ])
    #expect(try await store.pendingTextRecognitionIDs() == ["a", "b"])

    try await store.save([.stub(id: "a", textRecognition: .recognized([]))])

    #expect(try await store.pendingTextRecognitionIDs() == ["b"])
  }

  @Test("식별자로 저장된 이미지를 읽고 없는 식별자는 뺀다")
  func readsImagesByID() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let pending = IndexedImage.stub(
      id: "a",
      labels: [ImageLabel(identifier: "receipt", confidence: 0.5)],
      textRecognition: .pending
    )
    try await store.save([pending, .stub(id: "b")])

    #expect(try await store.images(ids: ["a", "missing"]) == [pending])
  }

  @Test("같은 식별자를 다시 저장하면 새 결과로 바꾼다")
  func replacesExistingImage() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([.stub(id: "a", categories: [.receipt, .document])])

    let updated = IndexedImage.stub(
      id: "a",
      labels: [ImageLabel(identifier: "food", confidence: 0.8)],
      categories: [.food]
    )
    try await store.save([updated])

    #expect(try await store.images(in: .food) == [updated])
    #expect(try await store.images(in: .receipt).isEmpty)
    #expect(try await store.categoryCounts() == [.food: 1])
  }

  @Test("같은 배치에 같은 식별자가 있으면 마지막 결과를 쓴다")
  func usesLastDuplicateInBatch() async throws {
    let store = try PhotoStoreClientImpl.inMemory()

    try await store.save([.stub(id: "a", categories: [.receipt]), .stub(id: "a", categories: [.chat])])

    #expect(try await store.categoryCounts() == [.chat: 1])
  }

  @Test("여행 카테고리는 이미지 카테고리로 저장하지 않는다")
  func ignoresTravelCategory() async throws {
    let store = try PhotoStoreClientImpl.inMemory()

    try await store.save([.stub(id: "a", categories: [.travel, .food])])

    #expect(try await store.images(in: .travel).isEmpty)
    #expect(try await store.images(in: .food).first?.categories == [.food])
    #expect(try await store.categoryCounts() == [.food: 1])
  }

  @Test("카테고리 이미지를 최신순으로, 생성일 없는 이미지는 맨 뒤로 돌려준다")
  func ordersNewestFirst() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "old", creationDate: Date(timeIntervalSince1970: 100), categories: [.chat]),
      .stub(id: "undated", creationDate: nil, categories: [.chat]),
      .stub(id: "new", creationDate: Date(timeIntervalSince1970: 200), categories: [.chat]),
      .stub(id: "other", creationDate: Date(timeIntervalSince1970: 300), categories: [.map]),
    ])

    #expect(try await store.images(in: .chat).map(\.id) == ["new", "old", "undated"])
  }

  @Test("카테고리별 이미지 수를 세고, 없는 카테고리는 뺀다")
  func countsByCategory() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "a", categories: [.receipt, .document]),
      .stub(id: "b", categories: [.receipt]),
      .stub(id: "c", categories: []),
    ])

    #expect(try await store.categoryCounts() == [.receipt: 2, .document: 1])
  }

  @Test("지운 이미지는 목록·개수·식별자에서 빠지고 없는 식별자는 무시한다")
  func deletesImages() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([.stub(id: "a", categories: [.receipt]), .stub(id: "b", categories: [.receipt])])

    try await store.delete(ids: ["a", "missing"])

    #expect(try await store.indexedIDs() == ["b"])
    #expect(try await store.images(in: .receipt).map(\.id) == ["b"])
    #expect(try await store.categoryCounts() == [.receipt: 1])
  }

  @Test("여행을 통째로 바꾸고 시작 시각 순으로 돌려주며, 수도 같이 바뀐다")
  func replacesTrips() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let jeju = Trip(
      assetIDs: ["j1", "j2"],
      startDate: Date(timeIntervalSince1970: 1000),
      endDate: Date(timeIntervalSince1970: 2000),
      center: Coordinate(latitude: 33.5, longitude: 126.5)
    )
    let busan = Trip(
      assetIDs: ["b1"],
      startDate: Date(timeIntervalSince1970: 100),
      endDate: Date(timeIntervalSince1970: 200),
      center: Coordinate(latitude: 35.1, longitude: 129.0)
    )
    try await store.replaceTrips([busan])

    try await store.replaceTrips([jeju, busan])
    #expect(try await store.trips() == [busan, jeju])
    #expect(try await store.tripCount() == 2)

    try await store.replaceTrips([jeju])
    #expect(try await store.trips() == [jeju])
    #expect(try await store.tripCount() == 1)
  }

  @Test("시작 시각이 같은 여행은 끝 시각 순으로 돌려준다")
  func ordersTripsWithSameStartByEnd() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let start = Date(timeIntervalSince1970: 1000)
    let long = Trip(
      assetIDs: ["l1"],
      startDate: start,
      endDate: Date(timeIntervalSince1970: 3000),
      center: Coordinate(latitude: 33.5, longitude: 126.5)
    )
    let short = Trip(
      assetIDs: ["s1"],
      startDate: start,
      endDate: Date(timeIntervalSince1970: 2000),
      center: Coordinate(latitude: 35.1, longitude: 129.0)
    )

    try await store.replaceTrips([long, short])

    #expect(try await store.trips() == [short, long])
  }

  @Test("파일 저장소는 다시 열어도 결과가 남는다")
  func persistsToFile() async throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
      .appending(path: "PhotoStore.store")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let image = IndexedImage.stub(id: "a", categories: [.receipt])
    let pending = IndexedImage.stub(id: "b", textRecognition: .pending, categories: [.receipt])

    try await PhotoStoreClientImpl(url: url).save([image, pending])

    let reopened = try PhotoStoreClientImpl(url: url)
    #expect(try await reopened.images(in: .receipt) == [image, pending])
    #expect(try await reopened.pendingTextRecognitionIDs() == ["b"])
  }

  @Test("OCR 상태 속성이 생기기 전 형식의 행은 줄이 있으면 읽음, 없으면 대상 아님으로 읽고 대기에 넣지 않는다")
  func readsRowsSavedBeforeTextRecognitionState() async throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
      .appending(path: "PhotoStore.store")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let lines = [
      RecognizedTextLine(text: "합계 9,000", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)),
      RecognizedTextLine(text: "영수증", confidence: 0.8, boundingBox: CGRect(x: 0, y: 0.2, width: 1, height: 0.1)),
    ]
    // 이전 빌드가 저장한 것처럼 `needsTextRecognition` 을 기본값(false)으로 둔 행을 직접 넣고, 컨테이너를 놓은 뒤 다시 연다.
    do {
      let container = try ModelContainer(
        for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
      )
      let context = ModelContext(container)
      let encoder = PropertyListEncoder()
      for (id, data) in try [("read", encoder.encode(lines)), ("photo", nil)] as [(String, Data?)] {
        let stored = StoredImage(assetID: id)
        stored.labelsData = try encoder.encode([ImageLabel]())
        stored.textLinesData = data
        context.insert(stored)
        stored.memberships = [StoredCategoryMembership(category: ImageCategory.receipt.rawValue)]
      }
      try context.save()
    }

    let store = try PhotoStoreClientImpl(url: url)

    let byCategory = try await Dictionary(uniqueKeysWithValues: store.images(in: .receipt).map { (
      $0.id,
      $0.textRecognition
    ) })
    let byID = try await Dictionary(uniqueKeysWithValues: store.images(ids: ["read", "photo"]).map { (
      $0.id,
      $0.textRecognition
    ) })
    let expected: [ImageAsset.ID: TextRecognition] = ["read": .recognized(lines), "photo": .notNeeded]
    #expect(byCategory == expected)
    #expect(byID == expected)
    #expect(try await store.pendingTextRecognitionIDs().isEmpty)
  }

  @Test("저장 폴더를 기기 백업에서 뺀다")
  func excludesFolderFromBackup() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }

    _ = try PhotoStoreClientImpl(url: folder.appending(path: "PhotoStore.store"))

    #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  }
}
