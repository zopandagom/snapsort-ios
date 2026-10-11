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

  @Test("정해 둔 실패를 던진다")
  func throwsConfiguredError() async {
    let fake = PhotoStoreClientFake(error: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.save([])
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.trips()
    }
  }
}
