import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import Testing

/// 캡처 묶음 값·소급·목록. Impl 과 Fake 가 같은 동작인지 같은 테스트로 본다.
/// OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct PhotoStoreCaptureGroupTests {
  @Test("추출 안 함·못 찾음·찾음(여러 지역 포함)을 구분해 같은 값으로 다시 읽는다", arguments: StoreKind.allCases)
  func roundTripsCaptureGroupStates(kind: StoreKind) async throws {
    let images = [
      CaptureGroupStoreFixture.image("none", .shopping, groups: nil),
      CaptureGroupStoreFixture.image("notFound", .shopping, groups: .empty),
      CaptureGroupStoreFixture.image("shopping", .shopping, groups: CaptureGroupStoreFixture.shopping),
      CaptureGroupStoreFixture.image("chat", .chat, groups: CaptureGroupStoreFixture.chat),
      CaptureGroupStoreFixture.image("map", .map, groups: CaptureGroupStoreFixture.map),
      CaptureGroupStoreFixture.image("mapNotFound", .map, groups: .empty),
    ]
    let store = try await kind.make(images)
    defer { store.remove() }

    #expect(try await Set(store.client.images(ids: Set(images.map(\.id)))) == Set(images))
    #expect(try await Set(store.client.images(in: .map)) == Set(images.filter { $0.categories.contains(.map) }))
    let map = try #require(try await store.client.images(ids: ["map"]).first)
    #expect(map.captureGroups?.regions.count == 2)
  }

  @Test("쇼핑·대화·지도로 분류돼 글자를 읽었을 때만 값을 담고, 카테고리에 없는 필드는 비운다", arguments: StoreKind.allCases)
  func keepsGroupsOnlyForRecognizedCaptureCategories(kind: StoreKind) async throws {
    let all = CaptureGroups(
      mall: CaptureGroupStoreFixture.mall,
      brand: CaptureGroupStoreFixture.brand,
      chatApp: .kakaoTalk,
      regions: CaptureGroupStoreFixture.map.regions
    )
    let images: [IndexedImage] = [
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.shopping], captureGroups: all),
      .stub(id: "notNeeded", categories: [.shopping], captureGroups: all),
      .stub(
        id: "document",
        textRecognition: .recognized(CaptureGroupStoreFixture.lines),
        categories: [.document],
        captureGroups: all
      ),
      .stub(
        id: "shopping",
        textRecognition: .recognized(CaptureGroupStoreFixture.lines),
        categories: [.shopping],
        captureGroups: all
      ),
      .stub(
        id: "chatMap",
        textRecognition: .recognized(CaptureGroupStoreFixture.lines),
        categories: [.chat, .map],
        captureGroups: all
      ),
    ]
    let store = try await kind.make(images)
    defer { store.remove() }

    let read = try await Dictionary(
      uniqueKeysWithValues: store.client.images(ids: Set(images.map(\.id))).map { ($0.id, $0.captureGroups) }
    )
    #expect(read == [
      "ocrPending": nil,
      "notNeeded": nil,
      "document": nil,
      "shopping": CaptureGroups(mall: CaptureGroupStoreFixture.mall, brand: CaptureGroupStoreFixture.brand),
      "chatMap": CaptureGroups(chatApp: .kakaoTalk, regions: CaptureGroupStoreFixture.map.regions),
    ])
  }

  @Test(
    "같은 행을 다시 저장하면 넘긴 값으로 바꾸고, 세 카테고리에서 빠지면 지우며, 다시 들어오면 추출 대기다",
    arguments: StoreKind.allCases
  )
  func replacesGroupsOnSave(kind: StoreKind) async throws {
    let store = try await kind.make([CaptureGroupStoreFixture.image(
      "a",
      .shopping,
      groups: CaptureGroupStoreFixture.shopping
    )])
    defer { store.remove() }
    let other = CaptureGroups(mall: ShoppingMall(id: "musinsa"), brand: nil)

    try await store.client.save([CaptureGroupStoreFixture.image("a", .shopping, groups: other)])
    #expect(try await store.client.images(ids: ["a"]).first?.captureGroups == other)

    try await store.client.save([.stub(
      id: "a",
      textRecognition: .recognized(CaptureGroupStoreFixture.lines),
      categories: [.document]
    )])
    #expect(try await store.client.images(ids: ["a"]).first?.captureGroups == nil)
    #expect(try await store.client.captureGroupItems(in: .shopping).isEmpty)

    try await store.client.save([CaptureGroupStoreFixture.image("a", .shopping, groups: nil)])
    #expect(try await store.client.captureGroupExtractionPendingIDs() == ["a"])
    #expect(try await store.client.captureGroupItems(in: .shopping).map(\.status) == [.checking])

    // 카테고리가 쇼핑에서 대화로 바뀌면 쇼핑 필드는 빠진다.
    try await store.client.save([CaptureGroupStoreFixture.image("a", .chat, groups: CaptureGroupStoreFixture.shopping)])
    #expect(try await store.client.images(ids: ["a"]).first?.captureGroups == .empty)
  }

  @Test("추출 대기는 셋 중 하나로 분류돼 글자를 읽었는데 추출하지 않은 행만 돌려준다", arguments: StoreKind.allCases)
  func listsCaptureGroupExtractionPending(kind: StoreKind) async throws {
    let store = try await kind.make(CaptureGroupStoreFixture.pendingCandidates())
    defer { store.remove() }

    #expect(try await store.client.captureGroupExtractionPendingIDs() == ["pending", "blank", "chat", "map"])
  }

  @Test("묶음 값 저장은 추출 대기 행만 바꾸고 행 카테고리로 제한하며, 이미 추출한 행·다른 행·없는 식별자는 무시한다", arguments: StoreKind.allCases)
  func savesGroupsOnlyForPendingRows(kind: StoreKind) async throws {
    let candidates = CaptureGroupStoreFixture.pendingCandidates()
    let store = try await kind.make(candidates)
    defer { store.remove() }
    let fresh = CaptureGroups(
      mall: CaptureGroupStoreFixture.mall,
      brand: CaptureGroupStoreFixture.brand,
      chatApp: .messages,
      regions: CaptureGroupStoreFixture.map.regions
    )

    try await store.client.saveCaptureGroups(Dictionary(uniqueKeysWithValues: (candidates.map(\.id) + ["missing"]).map {
      ($0, fresh)
    }))

    let read = try await Dictionary(
      uniqueKeysWithValues: store.client.images(ids: Set(candidates.map(\.id))).map { ($0.id, $0.captureGroups) }
    )
    #expect(read == [
      "pending": CaptureGroups(mall: CaptureGroupStoreFixture.mall, brand: CaptureGroupStoreFixture.brand),
      "blank": CaptureGroups(chatApp: .messages),
      "chat": CaptureGroups(chatApp: .messages),
      "map": CaptureGroups(regions: CaptureGroupStoreFixture.map.regions),
      "extracted": CaptureGroupStoreFixture.shopping,
      "ocrPending": nil,
      "notNeeded": nil,
      "document": nil,
    ])
    #expect(try await store.client.captureGroupExtractionPendingIDs().isEmpty)
    #expect(try await store.client.indexedIDs() == Set(candidates.map(\.id)))
  }

  @Test("목록은 최신순이고 OCR 대기·추출 대기는 확인 중, 글자를 읽지 않으면 빈 값이며, 세 카테고리 밖은 빈 배열이다", arguments: StoreKind.allCases)
  func listsItemsNewestFirst(kind: StoreKind) async throws {
    let store = try await kind.make([
      CaptureGroupStoreFixture.image("undated", .shopping, groups: nil, created: nil),
      CaptureGroupStoreFixture.image(
        "old",
        .shopping,
        groups: CaptureGroupStoreFixture.shopping,
        created: 1_600_000_000
      ),
      .stub(
        id: "ocrPending",
        creationDate: Date(timeIntervalSince1970: 1_800_000_000),
        textRecognition: .pending,
        categories: [.shopping]
      ),
      .stub(id: "notNeeded", creationDate: Date(timeIntervalSince1970: 1_700_000_000), categories: [.shopping]),
      CaptureGroupStoreFixture.image("sameTimeB", .shopping, groups: .empty, created: 1_650_000_000),
      CaptureGroupStoreFixture.image("sameTimeA", .shopping, groups: nil, created: 1_650_000_000),
      CaptureGroupStoreFixture.image("map", .map, groups: CaptureGroupStoreFixture.map),
      .stub(id: "document", textRecognition: .recognized(CaptureGroupStoreFixture.lines), categories: [.document]),
    ])
    defer { store.remove() }

    let items = try await store.client.captureGroupItems(in: .shopping)

    #expect(items.map(\.id) == ["ocrPending", "notNeeded", "sameTimeA", "sameTimeB", "old", "undated"])
    #expect(items.map(\.status) == [
      .checking, .extracted(.empty), .checking, .extracted(.empty), .extracted(CaptureGroupStoreFixture.shopping),
      .checking,
    ])
    #expect(items[1].asset.creationDate == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(try await store.client.captureGroupItems(in: .map).map(\.id) == ["map"])
    #expect(try await store.client.captureGroupItems(in: .document).isEmpty)
    #expect(try await store.client.captureGroupItems(in: .receipt).isEmpty)
  }

  @Test(
    "기프티콘·영수증 값과 사용 여부는 캡처 묶음 값과 독립이라 서로의 쓰기가 지우지 않는다",
    arguments: StoreKind.allCases
  )
  func groupsAreIndependentOfGifticonAndReceipt(kind: StoreKind) async throws {
    let partial = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let complete = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "예시카페")
    let chatGifticon = IndexedImage.stub(
      id: "chatGifticon",
      textRecognition: .recognized(CaptureGroupStoreFixture.lines),
      categories: [.gifticon, .chat],
      captureGroups: CaptureGroupStoreFixture.chat
    )
    let shoppingReceipt = IndexedImage.stub(
      id: "shoppingReceipt",
      textRecognition: .recognized(CaptureGroupStoreFixture.lines),
      categories: [.receipt, .shopping],
      captureGroups: CaptureGroupStoreFixture.shopping
    )
    let pendingGroups = IndexedImage.stub(
      id: "pendingGroups",
      textRecognition: .recognized(CaptureGroupStoreFixture.lines),
      categories: [.gifticon, .receipt, .map],
      gifticon: complete,
      gifticonModelFill: .done,
      receipt: ReceiptStoreFixture.found
    )
    let store = try await kind.make([chatGifticon, shoppingReceipt, pendingGroups], usedIDs: ["pendingGroups"])
    defer { store.remove() }

    try await store.client.saveGifticons(["chatGifticon": partial])
    try await store.client.saveGifticonModelFills(["chatGifticon": .filled(complete)])
    #expect(try await store.client.setGifticonUsed(true, id: "chatGifticon"))
    try await store.client.saveReceipts(["shoppingReceipt": ReceiptStoreFixture.found])

    let chat = try #require(try await store.client.images(ids: ["chatGifticon"]).first)
    #expect(chat.gifticon == complete)
    #expect(chat.captureGroups == CaptureGroupStoreFixture.chat)
    let shopping = try #require(try await store.client.images(ids: ["shoppingReceipt"]).first)
    #expect(shopping.receipt == ReceiptStoreFixture.found)
    #expect(shopping.captureGroups == CaptureGroupStoreFixture.shopping)
    #expect(try await store.client.captureGroupExtractionPendingIDs() == ["pendingGroups"])

    try await store.client.saveCaptureGroups(["pendingGroups": CaptureGroupStoreFixture.map])

    let map = try #require(try await store.client.images(ids: ["pendingGroups"]).first)
    #expect(map.captureGroups == CaptureGroupStoreFixture.map)
    #expect(map.gifticon == complete)
    #expect(map.gifticonModelFill == .done)
    #expect(map.receipt == ReceiptStoreFixture.found)
    let used = try await Dictionary(uniqueKeysWithValues: store.client.gifticons().map { ($0.id, $0.isUsed) })
    #expect(used == ["chatGifticon": true, "pendingGroups": true])
  }
}

/// 캡처 묶음 저장 테스트의 이미지 준비. OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
enum CaptureGroupStoreFixture {
  static let lines = [
    RecognizedTextLine(text: "예시 화면", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)),
  ]
  static let mall = ShoppingMall(id: "coupang")!
  static let brand = ShoppingBrand(id: "nike")!
  static let shopping = CaptureGroups(mall: mall, brand: brand)
  static let chat = CaptureGroups(chatApp: .kakaoTalk)
  static let map = CaptureGroups(regions: [KoreanRegion(id: "seoul:강남구")!, KoreanRegion(id: "busan:해운대구")!])

  /// 읽음 행. `created` 는 1970 부터 센 초.
  static func image(
    _ id: String,
    _ category: ImageCategory,
    groups: CaptureGroups?,
    created: TimeInterval? = 1_700_000_000
  ) -> IndexedImage {
    .stub(
      id: id,
      creationDate: created.map { Date(timeIntervalSince1970: $0) },
      textRecognition: .recognized(self.lines),
      categories: [category],
      captureGroups: groups
    )
  }

  /// 추출 대기 판정 후보: 대기 넷(쇼핑·빈 줄 대화·대화·지도)과 대기가 아닌 넷(추출함·OCR 대기·OCR 대상 아님·문서).
  static func pendingCandidates() -> [IndexedImage] {
    [
      self.image("pending", .shopping, groups: nil),
      .stub(id: "blank", textRecognition: .recognized([]), categories: [.chat]),
      self.image("chat", .chat, groups: nil),
      self.image("map", .map, groups: nil),
      self.image("extracted", .shopping, groups: self.shopping),
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.shopping]),
      .stub(id: "notNeeded", categories: [.map]),
      .stub(id: "document", textRecognition: .recognized(self.lines), categories: [.document]),
    ]
  }
}
