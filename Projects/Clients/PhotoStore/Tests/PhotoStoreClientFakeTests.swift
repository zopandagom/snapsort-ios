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
      gifticon: found,
      gifticonModelFill: .done
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

  @Test("Impl 처럼 만료일이 기준일과 같거나 늦은 기프티콘을 만료일 오름차순(같으면 식별자 순)으로 돌려준다")
  func listsUpcomingExpiries() async throws {
    let date = { (year: Int, month: Int, day: Int) throws -> LocalDate in
      try #require(LocalDate(year: year, month: month, day: day))
    }
    let gifticon = { (id: String, expiryDate: LocalDate?) in
      IndexedImage.stub(
        id: id,
        textRecognition: .recognized([]),
        categories: [.gifticon],
        gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: nil)
      )
    }
    let fake = try PhotoStoreClientFake(images: [
      gifticon("late", date(2027, 1, 5)),
      gifticon("b", date(2026, 12, 31)),
      gifticon("a", date(2026, 12, 31)),
      gifticon("today", date(2026, 10, 19)),
      gifticon("yesterday", date(2026, 10, 18)),
      gifticon("notFound", nil),
      IndexedImage.stub(id: "notExtracted", textRecognition: .recognized([]), categories: [.gifticon]),
    ])

    let expiries = try await fake.upcomingGifticonExpiries(from: date(2026, 10, 19))

    #expect(expiries.map(\.imageID) == ["today", "a", "b", "late"])
    #expect(try expiries.first == GifticonExpiry(imageID: "today", expiryDate: date(2026, 10, 19)))
  }

  @Test("만료 예정 조회 훅은 호출 번호를 0부터 받고, 기다리는 동안 바뀐 저장소가 아니라 훅 전에 계산한 값을 돌려준다")
  func returnsUpcomingExpiriesComputedBeforeHook() async throws {
    let expiryDate = try #require(LocalDate(year: 2026, month: 12, day: 31))
    let gifticon = IndexedImage.stub(
      id: "a",
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: nil)
    )
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(onUpcomingGifticonExpiries: { index in
      indexes.withLock { $0.append(index) }
      if index == 0 {
        try? await fake.value?.save([gifticon])
      }
    })
    fake.set(instance)

    let first = try await instance.upcomingGifticonExpiries(from: expiryDate)
    let second = try await instance.upcomingGifticonExpiries(from: expiryDate)

    #expect(first.isEmpty)
    #expect(second == [GifticonExpiry(imageID: "a", expiryDate: expiryDate)])
    #expect(indexes.withLock { $0 } == [0, 1])
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
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.upcomingGifticonExpiries(from: LocalDate(Date(), calendar: .current))
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.gifticonModelFillPendingIDs()
    }
  }
}

// 카테고리 화면용 메타데이터 조회 `assets(in:)`.
extension PhotoStoreClientFakeTests {
  @Test("Fake 도 images(in:) 와 같은 순서로 메타데이터를 돌려준다")
  func fakeAssetsMatchImagesOrder() async throws {
    let fake = PhotoStoreClientFake(images: [
      .stub(id: "old", creationDate: Date(timeIntervalSince1970: 100), categories: [.chat]),
      .stub(id: "undated", creationDate: nil, categories: [.chat]),
      .stub(id: "sameB", creationDate: Date(timeIntervalSince1970: 150), categories: [.chat]),
      .stub(id: "new", creationDate: Date(timeIntervalSince1970: 200), categories: [.chat]),
      .stub(id: "sameA", creationDate: Date(timeIntervalSince1970: 150), categories: [.chat]),
      .stub(id: "food", categories: [.food, .travel]),
    ])

    let assets = try await fake.assets(in: .chat)

    #expect(assets.map(\.id) == ["new", "sameA", "sameB", "old", "undated"])
    #expect(try await assets == fake.images(in: .chat).map(\.asset))
    #expect(try await fake.assets(in: .travel).isEmpty)
    #expect(fake.assetsCallCount == 2)
  }

  @Test("모든 호출 실패를 정하면 던진다")
  func fakeAssetsThrowsError() async {
    let fake = PhotoStoreClientFake(images: [.stub(id: "a", categories: [.chat])], error: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.assets(in: .chat)
    }
  }

  @Test("정한 번째 호출만 실패하고 다음 호출은 성공한다")
  func fakeAssetsErrorsByCall() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = PhotoStoreClientFake(
      images: [.stub(id: "a", categories: [.chat])],
      assetsErrors: [1: .failed],
      onAssets: { index in indexes.withLock { $0.append(index) } }
    )

    #expect(try await fake.assets(in: .chat).map(\.id) == ["a"])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.assets(in: .chat)
    }
    #expect(try await fake.assets(in: .chat).map(\.id) == ["a"])
    #expect(fake.assetsCallCount == 3)
    // 실패한 호출에서는 훅을 부르지 않는다.
    #expect(indexes.withLock { $0 } == [0, 2])
  }

  @Test("메타데이터 조회 훅을 기다리는 동안 바뀐 저장소가 아니라 훅 전에 계산한 값을 돌려준다")
  func fakeAssetsComputedBeforeHook() async throws {
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(onAssets: { index in
      if index == 0 {
        try? await fake.value?.save([.stub(id: "a", categories: [.chat])])
      }
    })
    fake.set(instance)

    #expect(try await instance.assets(in: .chat).isEmpty)
    #expect(try await instance.assets(in: .chat).map(\.id) == ["a"])
  }
}

/// 훅이 만들기 전의 대역을 참조하도록 나중에 채운다.
private final class Later<Value: Sendable>: Sendable {
  private let storage = Mutex<Value?>(nil)

  var value: Value? {
    self.storage.withLock { $0 }
  }

  func set(_ value: Value) {
    self.storage.withLock { $0 = value }
  }
}
