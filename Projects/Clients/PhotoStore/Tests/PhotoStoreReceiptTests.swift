import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import Testing

/// 영수증 추출 값·소급·목록. Impl 과 Fake 가 같은 동작인지 같은 테스트로 본다.
/// 가게 이름과 OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct PhotoStoreReceiptTests {
  @Test("추출 안 함·못 찾음·찾음(취소 포함)을 구분해 같은 값으로 다시 읽는다", arguments: StoreKind.allCases)
  func roundTripsReceiptStates(kind: StoreKind) async throws {
    let images = [
      ReceiptStoreFixture.receipt("none", info: nil),
      ReceiptStoreFixture.receipt("notFound", info: .empty),
      ReceiptStoreFixture.receipt("found", info: ReceiptStoreFixture.found),
      ReceiptStoreFixture.receipt("storeOnly", info: ReceiptInfo(storeName: "예시상점", amount: nil, isCancelled: false)),
      ReceiptStoreFixture.receipt("cancelled", info: ReceiptInfo(
        storeName: nil,
        amount: ReceiptAmount(minorUnits: 4520, currency: .usd),
        isCancelled: true
      )),
    ]
    let store = try await kind.make(images)
    defer { store.remove() }

    #expect(try await Set(store.client.images(ids: Set(images.map(\.id)))) == Set(images))
    #expect(try await Set(store.client.images(in: .receipt)) == Set(images))
  }

  @Test("영수증으로 분류돼 글자를 읽었을 때만 영수증 값을 담는다", arguments: StoreKind.allCases)
  func keepsReceiptOnlyForRecognizedReceipts(kind: StoreKind) async throws {
    let images: [IndexedImage] = [
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.receipt], receipt: ReceiptStoreFixture.found),
      .stub(id: "notNeeded", categories: [.receipt], receipt: ReceiptStoreFixture.found),
      .stub(
        id: "notReceipt",
        textRecognition: .recognized(ReceiptStoreFixture.lines),
        categories: [.document],
        receipt: ReceiptStoreFixture.found
      ),
    ]
    #expect(images.allSatisfy { $0.receipt == nil })
    let store = try await kind.make(images)
    defer { store.remove() }

    #expect(try await store.client.images(ids: Set(images.map(\.id))).allSatisfy { $0.receipt == nil })
  }

  @Test("같은 행을 다시 저장하면 영수증 값을 넘긴 값으로 바꾸고, 영수증에서 빠지면 지우며, 다시 영수증이 되면 추출 대기다", arguments: StoreKind.allCases)
  func replacesReceiptOnSave(kind: StoreKind) async throws {
    let store = try await kind.make([ReceiptStoreFixture.receipt("a")])
    defer { store.remove() }
    let other = ReceiptInfo(
      storeName: "예시상점",
      amount: ReceiptAmount(minorUnits: 4500, currency: .krw),
      isCancelled: false
    )

    try await store.client.save([ReceiptStoreFixture.receipt("a", info: other)])
    #expect(try await store.client.images(ids: ["a"]).first?.receipt == other)

    try await store.client.save([.stub(
      id: "a",
      textRecognition: .recognized(ReceiptStoreFixture.lines),
      categories: [.document]
    )])
    #expect(try await store.client.images(ids: ["a"]).first?.receipt == nil)
    #expect(try await store.client.receipts().isEmpty)

    try await store.client.save([ReceiptStoreFixture.receipt("a", info: nil)])
    #expect(try await store.client.receiptExtractionPendingIDs() == ["a"])
    #expect(try await store.client.receipts().map(\.status) == [.checking])
  }

  @Test("추출 대기는 영수증으로 분류돼 글자를 읽었는데 추출하지 않은 행만 돌려준다", arguments: StoreKind.allCases)
  func listsReceiptExtractionPending(kind: StoreKind) async throws {
    let store = try await kind.make(ReceiptStoreFixture.pendingCandidates())
    defer { store.remove() }

    #expect(try await store.client.receiptExtractionPendingIDs() == ["pending", "blank"])
  }

  @Test("영수증 값 저장은 추출 대기 행만 바꾸고 이미 추출한 행·다른 행·없는 식별자는 무시한다", arguments: StoreKind.allCases)
  func savesReceiptsOnlyForPendingRows(kind: StoreKind) async throws {
    let candidates = ReceiptStoreFixture.pendingCandidates()
    let store = try await kind.make(candidates)
    defer { store.remove() }
    let fresh = ReceiptInfo(
      storeName: "새 가게",
      amount: ReceiptAmount(minorUnits: 1234, currency: .jpy),
      isCancelled: false
    )

    try await store.client.saveReceipts(Dictionary(uniqueKeysWithValues: (candidates.map(\.id) + ["missing"]).map {
      ($0, fresh)
    }))

    let read = try await Dictionary(
      uniqueKeysWithValues: store.client.images(ids: Set(candidates.map(\.id))).map { ($0.id, $0.receipt) }
    )
    #expect(read == [
      "pending": fresh, "blank": fresh, "extracted": ReceiptStoreFixture.found, "ocrPending": nil, "notNeeded": nil,
      "gifticon": nil,
    ])
    #expect(try await store.client.receiptExtractionPendingIDs().isEmpty)
    #expect(try await store.client.indexedIDs() == Set(candidates.map(\.id)))
  }

  @Test("영수증 목록은 최신순이고 OCR 대기·추출 대기는 확인 중, 글자를 읽지 않는 영수증은 빈 값이다", arguments: StoreKind.allCases)
  func listsReceiptsNewestFirst(kind: StoreKind) async throws {
    let store = try await kind.make([
      ReceiptStoreFixture.receipt("undated", info: nil, created: nil),
      ReceiptStoreFixture.receipt("old", info: ReceiptStoreFixture.found, created: 1_600_000_000),
      .stub(
        id: "ocrPending",
        creationDate: Date(timeIntervalSince1970: 1_800_000_000),
        textRecognition: .pending,
        categories: [.receipt]
      ),
      .stub(id: "notNeeded", creationDate: Date(timeIntervalSince1970: 1_700_000_000), categories: [.receipt]),
      ReceiptStoreFixture.receipt("sameTimeB", info: .empty, created: 1_650_000_000),
      ReceiptStoreFixture.receipt("sameTimeA", info: nil, created: 1_650_000_000),
      .stub(id: "gifticon", textRecognition: .recognized(ReceiptStoreFixture.lines), categories: [.gifticon]),
    ])
    defer { store.remove() }

    let items = try await store.client.receipts()

    #expect(items.map(\.id) == ["ocrPending", "notNeeded", "sameTimeA", "sameTimeB", "old", "undated"])
    #expect(items.map(\.status) == [
      .checking, .extracted(.empty), .checking, .extracted(.empty), .extracted(ReceiptStoreFixture.found), .checking,
    ])
    #expect(items[1].asset.creationDate == Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test("기프티콘이면서 영수증인 행은 두 추출 값을 따로 저장·대기하고, 기프티콘 소급·보강·사용 여부 쓰기가 영수증 값을 지우지 않는다", arguments: StoreKind.allCases)
  func gifticonAndReceiptValuesAreIndependent(kind: StoreKind) async throws {
    let both = IndexedImage.stub(
      id: "both",
      textRecognition: .recognized(ReceiptStoreFixture.lines),
      categories: [.gifticon, .receipt]
    )
    let store = try await kind.make([both])
    defer { store.remove() }
    let partial = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let complete = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "예시카페")
    #expect(try await store.client.gifticonExtractionPendingIDs() == ["both"])
    #expect(try await store.client.receiptExtractionPendingIDs() == ["both"])

    try await store.client.saveReceipts(["both": ReceiptStoreFixture.found])
    #expect(try await store.client.images(ids: ["both"]).first?.gifticon == nil)
    #expect(try await store.client.gifticonExtractionPendingIDs() == ["both"])

    try await store.client.saveGifticons(["both": partial])
    try await store.client.saveGifticonModelFills(["both": .filled(complete)])
    #expect(try await store.client.setGifticonUsed(true, id: "both"))

    let image = try #require(try await store.client.images(ids: ["both"]).first)
    #expect(image.gifticon == complete)
    #expect(image.receipt == ReceiptStoreFixture.found)
    #expect(try await store.client.receipts().map(\.status) == [.extracted(ReceiptStoreFixture.found)])
    #expect(try await store.client.receiptExtractionPendingIDs().isEmpty)
  }
}

/// 영수증 저장 테스트의 이미지 준비. 가게 이름과 OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
enum ReceiptStoreFixture {
  static let lines = [
    RecognizedTextLine(text: "합계 9,000", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)),
  ]
  static let found = ReceiptInfo(
    storeName: "(주)예시마트",
    amount: ReceiptAmount(minorUnits: 9000, currency: .krw),
    isCancelled: false
  )

  /// 영수증 읽음 행. `created` 는 1970 부터 센 초.
  static func receipt(
    _ id: String,
    info: ReceiptInfo? = Self.found,
    created: TimeInterval? = 1_700_000_000
  ) -> IndexedImage {
    .stub(
      id: id,
      creationDate: created.map { Date(timeIntervalSince1970: $0) },
      textRecognition: .recognized(self.lines),
      categories: [.receipt],
      receipt: info
    )
  }

  /// 추출 대기 판정 후보: 대기 둘(줄 있음·빈 줄)과 대기가 아닌 넷(추출함·OCR 대기·OCR 대상 아님·기프티콘).
  static func pendingCandidates() -> [IndexedImage] {
    [
      self.receipt("pending", info: nil),
      .stub(id: "blank", textRecognition: .recognized([]), categories: [.receipt]),
      self.receipt("extracted"),
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.receipt]),
      .stub(id: "notNeeded", categories: [.receipt]),
      .stub(id: "gifticon", textRecognition: .recognized(self.lines), categories: [.gifticon]),
    ]
  }
}
