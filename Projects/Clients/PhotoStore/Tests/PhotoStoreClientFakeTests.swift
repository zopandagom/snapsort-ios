import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
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

  @Test("Impl 처럼 OCR 대기 식별자와 식별자별 이미지를 돌려준다")
  func listsPendingAndImagesByIDLikeImpl() async throws {
    let pending = IndexedImage.stub(id: "a", textRecognition: .pending)
    let fake = PhotoStoreClientFake(images: [pending, .stub(id: "b"), .stub(id: "c", textRecognition: .recognized([]))])

    #expect(try await fake.pendingTextRecognitionIDs() == ["a"])
    #expect(try await fake.images(ids: ["a", "missing"]) == [pending])

    try await fake.save([.stub(id: "a", textRecognition: .recognized([]))])
    #expect(try await fake.pendingTextRecognitionIDs().isEmpty)
  }

  @Test("식별자 읽기에서 뺄 식별자를 정하면 그 식별자만 빼고, 풀면 다시 돌려준다")
  func hidesImagesFromIDReads() async throws {
    let fake = PhotoStoreClientFake(
      images: [.stub(id: "a", textRecognition: .pending), .stub(id: "b")],
      missingOnIDRead: ["a"]
    )

    #expect(try await fake.images(ids: ["a", "b"]).map(\.id) == ["b"])
    #expect(try await fake.pendingTextRecognitionIDs() == ["a"])
    fake.restoreIDReads()
    #expect(try await fake.images(ids: ["a", "b"]).map(\.id) == ["a", "b"])
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

  @Test("Impl 처럼 추출 대기 행만 돌려주고 추출 값 저장은 그 행만 바꾸며 요청을 기록한다")
  func savesGifticonsOnlyForPendingRowsLikeImpl() async throws {
    let found = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "스타벅스")
    let notFound = GifticonInfo(expiryDate: nil, redemptionPlace: nil)
    let pending = IndexedImage.stub(id: "pending", textRecognition: .recognized([]), categories: [.gifticon])
    let others: [IndexedImage] = [
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.gifticon]),
      .stub(id: "notNeeded", categories: [.gifticon]),
      .stub(id: "receipt", textRecognition: .recognized([]), categories: [.receipt]),
      .stub(id: "notFound", textRecognition: .recognized([]), categories: [.gifticon], gifticon: notFound),
    ]
    let fake = PhotoStoreClientFake(images: [pending] + others)

    #expect(try await fake.gifticonExtractionPendingIDs() == ["pending"])

    let request = Dictionary(uniqueKeysWithValues: (["pending", "missing"] + others.map(\.id)).map { ($0, found) })
    try await fake.saveGifticons(request)

    #expect(fake.images == ([.stub(
      id: "pending",
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: found
    )] + others).sorted { $0.id < $1.id })
    #expect(try await fake.gifticonExtractionPendingIDs().isEmpty)
    #expect(fake.savedGifticonBatches == [request])
  }

  @Test("추출 값 저장 전에 훅을 기다리고, 한도를 정하면 그 횟수만큼 저장한 뒤부터 실패한다")
  func callsHookAndFailsSavingGifticonsAfterLimit() async throws {
    let info = GifticonInfo(expiryDate: nil, redemptionPlace: "CU")
    let hookCalls = Mutex<[[ImageAsset.ID: GifticonInfo]]>([])
    let fake = PhotoStoreClientFake(
      images: [
        .stub(id: "a", textRecognition: .recognized([]), categories: [.gifticon]),
        .stub(id: "b", textRecognition: .recognized([]), categories: [.gifticon]),
      ],
      gifticonSaveLimit: 1,
      onSaveGifticons: { gifticons in hookCalls.withLock { $0.append(gifticons) } }
    )

    try await fake.saveGifticons(["a": info])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveGifticons(["b": info])
    }

    #expect(hookCalls.withLock { $0 } == [["a": info], ["b": info]])
    #expect(fake.savedGifticonBatches == [["a": info]])
    #expect(try await fake.gifticonExtractionPendingIDs() == ["b"])
  }

  @Test("소급 추출 실패를 정하면 추출 대기 조회·추출 값 저장만 실패하고 다른 호출과 저장 결과는 그대로다")
  func failsOnlyGifticonCallsWithGifticonError() async throws {
    let pending = IndexedImage.stub(id: "a", textRecognition: .recognized([]), categories: [.gifticon])
    let hookCalls = Mutex(0)
    let fake = PhotoStoreClientFake(
      images: [pending],
      gifticonError: .failed,
      onSaveGifticons: { _ in hookCalls.withLock { $0 += 1 } }
    )

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.gifticonExtractionPendingIDs()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveGifticons(["a": GifticonInfo(expiryDate: nil, redemptionPlace: "CU")])
    }
    try await fake.save([.stub(id: "b")])
    try await fake.delete(ids: ["missing"])

    #expect(hookCalls.withLock { $0 } == 1)
    #expect(fake.savedGifticonBatches.isEmpty)
    #expect(try await fake.images(ids: ["a"]) == [pending])
    #expect(try await fake.indexedIDs() == ["a", "b"])
    #expect(try await fake.pendingTextRecognitionIDs().isEmpty)
    #expect(fake.savedBatches.map { $0.map(\.id) } == [["b"]])
  }

  @Test("식별자 읽기 실패를 정하면 그 식별자를 포함한 읽기만 실패하고 다른 읽기·호출과 저장 결과는 그대로다")
  func failsOnlyIDReadsIncludingFailingIDs() async throws {
    let failing = IndexedImage.stub(id: "a", textRecognition: .recognized([]), categories: [.gifticon])
    let readable = IndexedImage.stub(id: "b", textRecognition: .recognized([]), categories: [.gifticon])
    let fake = PhotoStoreClientFake(images: [failing, readable], failingOnIDRead: ["a"])

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.images(ids: ["a"])
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.images(ids: ["a", "b"])
    }
    #expect(try await fake.images(ids: ["b"]) == [readable])
    #expect(fake.images == [failing, readable])

    let info = GifticonInfo(expiryDate: nil, redemptionPlace: "CU")
    #expect(try await fake.indexedIDs() == ["a", "b"])
    try await fake.save([.stub(id: "c")])
    try await fake.saveGifticons(["a": info])

    #expect(fake.savedBatches.map { $0.map(\.id) } == [["c"]])
    #expect(fake.savedGifticonBatches == [["a": info]])
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
