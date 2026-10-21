import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

struct PhotoStoreClientImplAssetsTests {
  @Test("카테고리 이미지의 메타데이터를 최신순(날짜 없음 맨 뒤, 같으면 식별자 순)으로 읽는다")
  func assetsInCategoryNewestFirst() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let same = Date(timeIntervalSince1970: 150)
    try await store.save([
      .stub(id: "old", creationDate: Date(timeIntervalSince1970: 100), categories: [.chat]),
      .stub(id: "undatedB", creationDate: nil, categories: [.chat]),
      .stub(id: "sameB", creationDate: same, categories: [.chat]),
      .stub(id: "new", creationDate: Date(timeIntervalSince1970: 200), categories: [.chat]),
      .stub(id: "undatedA", creationDate: nil, categories: [.chat]),
      .stub(id: "sameA", creationDate: same, categories: [.chat]),
    ])

    let assets = try await store.assets(in: .chat)

    #expect(assets.map(\.id) == ["new", "sameA", "sameB", "old", "undatedA", "undatedB"])
    #expect(try await assets == store.images(in: .chat).map(\.asset))
  }

  @Test("좌표·크기·스크린샷 여부를 저장한 그대로 돌려준다")
  func assetsKeepMetadata() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let screenshot = ImageAsset(
      id: "screenshot",
      creationDate: Date(timeIntervalSince1970: 200),
      coordinate: nil,
      pixelWidth: 1179,
      pixelHeight: 2556,
      isScreenshot: true
    )
    let photo = ImageAsset(
      id: "photo",
      creationDate: Date(timeIntervalSince1970: 100),
      coordinate: Coordinate(latitude: 37.5665, longitude: 126.978),
      pixelWidth: 4032,
      pixelHeight: 3024,
      isScreenshot: false
    )
    try await store.save([screenshot, photo].map { asset in
      IndexedImage(
        asset: asset,
        labels: [ImageLabel(identifier: "food", confidence: 0.9)],
        textRecognition: .notNeeded,
        categories: [.food],
        gifticon: nil,
        gifticonModelFill: .pending(failures: 0)
      )
    })

    #expect(try await store.assets(in: .food) == [screenshot, photo])
  }

  @Test("다른 카테고리 이미지는 빠지고 지운 이미지는 없다")
  func assetsOnlyInCategory() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      .stub(id: "a", categories: [.receipt, .document]),
      .stub(id: "b", categories: [.receipt]),
      .stub(id: "c", categories: [.chat]),
    ])
    try await store.delete(ids: ["a"])

    #expect(try await store.assets(in: .receipt).map(\.id) == ["b"])
    #expect(try await store.assets(in: .document).isEmpty)
    #expect(try await store.assets(in: .chat).map(\.id) == ["c"])
  }

  @Test("여행은 이미지 카테고리가 아니라 비어 있다")
  func assetsInTravelIsEmpty() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([.stub(id: "a", coordinate: Coordinate(latitude: 35.1, longitude: 129.0), categories: [
      .travel,
      .food,
    ])])

    #expect(try await store.assets(in: .travel).isEmpty)
    #expect(try await store.assets(in: .food).map(\.id) == ["a"])
  }

  @Test("OCR 줄을 디코딩하지 못하는 행도 목록에 나온다(images(in:) 는 던진다)")
  func assetsListRowWithUndecodableText() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      .appending(path: "PhotoStore.store")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // 저장소가 쓰지 않는 값을 직접 넣기 위해 Impl 스키마로 파일을 만들고 컨테이너를 놓은 뒤 저장소로 다시 연다.
    do {
      let container = try ModelContainer(
        for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
      )
      let context = ModelContext(container)
      let stored = StoredImage(assetID: "broken")
      stored.labelsData = try PropertyListEncoder().encode([ImageLabel]())
      stored.needsTextRecognition = true
      stored.textLinesData = Data("x".utf8)
      context.insert(stored)
      stored.memberships = [StoredCategoryMembership(category: ImageCategory.receipt.rawValue)]
      try context.save()
    }
    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.assets(in: .receipt).map(\.id) == ["broken"])
    await #expect(throws: PhotoStoreError.failed) {
      try await store.images(in: .receipt)
    }
  }
}
