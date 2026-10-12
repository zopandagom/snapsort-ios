import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
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
      textLines: [RecognizedTextLine(
        text: "유효기간 2026.12.31",
        confidence: 0.9,
        boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05)
      )],
      categories: [.gifticon, .document]
    )

    try await store.save([image])

    #expect(try await store.images(in: .gifticon) == [image])
    #expect(try await store.indexedIDs() == ["gifticon"])
  }

  @Test("OCR 하지 않은 이미지와 글자가 없던 이미지를 구분한다")
  func keepsDifferenceBetweenNoOCRAndNoText() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let notRecognized = IndexedImage.stub(id: "photo", textLines: nil, categories: [.food])
    let noText = IndexedImage.stub(id: "blank", textLines: [], categories: [.food])

    try await store.save([notRecognized, noText])

    let stored = try await store.images(in: .food)
    #expect(stored.first { $0.id == "photo" }?.textLines == nil)
    #expect(stored.first { $0.id == "blank" }?.textLines == [])
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

    try await PhotoStoreClientImpl(url: url).save([image])

    #expect(try await PhotoStoreClientImpl(url: url).images(in: .receipt) == [image])
  }

  @Test("저장 폴더를 기기 백업에서 뺀다")
  func excludesFolderFromBackup() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }

    _ = try PhotoStoreClientImpl(url: folder.appending(path: "PhotoStore.store"))

    #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  }
}
