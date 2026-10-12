import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing

struct PhotoStoreClientFakeTests {
  @Test("정해 둔 이미지로 카테고리 목록·개수·식별자를 돌려준다")
  func returnsConfiguredImages() async throws {
    let receipt = IndexedImage.stub(id: "a", categories: [.receipt, .document])
    let chat = IndexedImage.stub(id: "b", categories: [.chat])
    let fake = PhotoStoreClientFake(images: [receipt, chat])

    #expect(try await fake.images(in: .receipt) == [receipt])
    #expect(try await fake.categoryCounts() == [.receipt: 1, .document: 1, .chat: 1])
    #expect(try await fake.indexedIDs() == ["a", "b"])
  }

  @Test("카테고리 이미지를 Impl 과 같은 최신순으로 돌려준다")
  func ordersNewestFirstLikeImpl() async throws {
    let fake = PhotoStoreClientFake(images: [
      .stub(id: "old", creationDate: Date(timeIntervalSince1970: 100), categories: [.chat]),
      .stub(id: "undated", creationDate: nil, categories: [.chat]),
      .stub(id: "new", creationDate: Date(timeIntervalSince1970: 200), categories: [.chat]),
    ])

    #expect(try await fake.images(in: .chat).map(\.id) == ["new", "old", "undated"])
  }

  @Test("Impl 처럼 여행 카테고리는 목록·개수에서 뺀다")
  func ignoresTravelCategoryLikeImpl() async throws {
    let fake = PhotoStoreClientFake(images: [.stub(id: "a", categories: [.travel, .food])])

    #expect(try await fake.images(in: .travel).isEmpty)
    #expect(try await fake.categoryCounts() == [.food: 1])
  }

  @Test("저장·삭제·여행 교체를 조회에 반영하고 요청을 기록한다")
  func reflectsWritesAndRecordsRequests() async throws {
    let fake = PhotoStoreClientFake(images: [.stub(id: "a", categories: [.chat])])
    let trip = Trip(
      assetIDs: ["b"],
      startDate: Date(timeIntervalSince1970: 100),
      endDate: Date(timeIntervalSince1970: 200),
      center: Coordinate(latitude: 35.1, longitude: 129.0)
    )

    try await fake.save([.stub(id: "b", categories: [.food])])
    try await fake.delete(ids: ["a", "missing"])
    try await fake.replaceTrips([trip])

    #expect(try await fake.indexedIDs() == ["b"])
    #expect(try await fake.categoryCounts() == [.food: 1])
    #expect(try await fake.trips() == [trip])
    #expect(try await fake.tripCount() == 1)
    #expect(fake.savedBatches.map { $0.map(\.id) } == [["b"]])
    #expect(fake.deletedBatches == [["a", "missing"]])
    #expect(fake.replaceTripsCount == 1)
  }

  @Test("저장 한도를 정하면 그 횟수만큼 저장한 뒤부터 실패한다")
  func failsSavingAfterLimit() async throws {
    let fake = PhotoStoreClientFake(saveLimit: 1)

    try await fake.save([.stub(id: "a")])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.save([.stub(id: "b")])
    }

    #expect(try await fake.indexedIDs() == ["a"])
  }

  @Test("정해 둔 실패를 던진다")
  func throwsConfiguredError() async {
    let fake = PhotoStoreClientFake(error: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.save([])
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.trips()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.tripCount()
    }
  }
}
