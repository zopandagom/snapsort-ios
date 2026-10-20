import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

struct PhotoStoreClientImplGifticonTests {
  private static let lines = [
    RecognizedTextLine(
      text: "유효기간 2026.12.31",
      confidence: 0.9,
      boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)
    ),
  ]

  @Test("추출 안 함·못 찾음·찾음을 구분해 같은 값으로 다시 읽는다")
  func roundTripsGifticonStates() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let images: [IndexedImage] = try [
      Self.gifticon("none", gifticon: nil),
      Self.gifticon("notFound", gifticon: GifticonInfo(expiryDate: nil, redemptionPlace: nil)),
      Self.gifticon("leapDay", gifticon: GifticonInfo(expiryDate: Self.date(2028, 2, 29), redemptionPlace: "스타벅스")),
      Self.gifticon("newYear", gifticon: GifticonInfo(expiryDate: Self.date(2026, 1, 1), redemptionPlace: nil)),
      Self.gifticon("yearEnd", gifticon: GifticonInfo(expiryDate: Self.date(2026, 12, 31), redemptionPlace: "GS25")),
    ]

    try await store.save(images)

    #expect(try await Set(store.images(ids: Set(images.map(\.id)))) == Set(images))
    #expect(try await Set(store.images(in: .gifticon)) == Set(images))
  }

  @Test("같은 식별자를 다시 저장하면 추출 값을 넘긴 값으로 바꾼다")
  func replacesGifticonOnSave() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let found = try GifticonInfo(expiryDate: Self.date(2026, 12, 31), redemptionPlace: "스타벅스")
    try await store.save([Self.gifticon("a", gifticon: found)])

    try await store.save([Self.gifticon("a", gifticon: nil)])
    #expect(try await store.images(ids: ["a"]).first?.gifticon == nil)

    let other = GifticonInfo(expiryDate: nil, redemptionPlace: "CU")
    try await store.save([Self.gifticon("a", gifticon: other)])
    #expect(try await store.images(ids: ["a"]).first?.gifticon == other)
  }

  @Test("추출 대기는 기프티콘으로 분류돼 글자를 읽었는데 추출하지 않은 행만 돌려준다")
  func listsGifticonExtractionPending() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save(Self.pendingCandidates())

    #expect(try await store.gifticonExtractionPendingIDs() == ["pending", "blank"])
  }

  @Test("추출 값 저장은 추출 대기 행의 추출 값만 바꾸고 나머지 행과 없는 식별자는 무시한다")
  func savesGifticonsOnlyForPendingRows() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let candidates = try Self.pendingCandidates()
    try await store.save(candidates)
    let found = try GifticonInfo(expiryDate: Self.date(2027, 3, 1), redemptionPlace: "배스킨라빈스")

    try await store.saveGifticons(Dictionary(
      uniqueKeysWithValues: (candidates.map(\.id) + ["missing"]).map { ($0, found) }
    ))

    let stored = try await Dictionary(
      uniqueKeysWithValues: store.images(ids: Set(candidates.map(\.id))).map { ($0.id, $0) }
    )
    let expected = Dictionary(uniqueKeysWithValues: candidates.map { image in
      let isPending = image.id == "pending" || image.id == "blank"
      return (image.id, isPending ? Self.withGifticon(image, found) : image)
    })
    #expect(stored == expected)
    #expect(try await store.indexedIDs() == Set(candidates.map(\.id)))
    #expect(try await store.gifticonExtractionPendingIDs().isEmpty)
  }

  @Test("규칙 버전이 다르거나 만료일을 해석하지 못하는 행은 추출하지 않은 것으로 읽고 다시 저장할 수 있다")
  func treatsStaleOrUnreadableRowsAsNotExtracted() async throws {
    let url = Self.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // 저장소가 쓰지 않는 값을 직접 넣기 위해 Impl 스키마로 파일을 만들고 컨테이너를 놓은 뒤 저장소로 다시 연다.
    do {
      let container = try ModelContainer(
        for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
      )
      let context = ModelContext(container)
      let encoder = PropertyListEncoder()
      let rows: [String: (version: Int, day: Int)] = [
        "oldVersion": (GifticonExtractor.rulesVersion + 1, 20_261_231),
        "badDay": (GifticonExtractor.rulesVersion, 20_260_230),
        "valid": (GifticonExtractor.rulesVersion, 20_261_231),
      ]
      for (id, row) in rows {
        let stored = StoredImage(assetID: id)
        stored.labelsData = try encoder.encode([ImageLabel]())
        stored.needsTextRecognition = true
        stored.textLinesData = try encoder.encode(Self.lines)
        stored.gifticonRulesVersion = row.version
        stored.gifticonExpiryDay = row.day
        stored.gifticonRedemptionPlace = "스타벅스"
        context.insert(stored)
        stored.memberships = [StoredCategoryMembership(category: ImageCategory.gifticon.rawValue)]
      }
      try context.save()
    }
    let store = try PhotoStoreClientImpl(url: url)
    let valid = try GifticonInfo(expiryDate: Self.date(2026, 12, 31), redemptionPlace: "스타벅스")

    let read = try await Dictionary(uniqueKeysWithValues: store.images(in: .gifticon).map { ($0.id, $0.gifticon) })
    #expect(read == ["oldVersion": nil, "badDay": nil, "valid": valid])
    #expect(try await store.gifticonExtractionPendingIDs() == ["oldVersion", "badDay"])

    let fresh = try GifticonInfo(expiryDate: Self.date(2027, 1, 31), redemptionPlace: nil)
    try await store.saveGifticons(["oldVersion": fresh, "badDay": fresh, "valid": fresh])

    let rewritten = try await Dictionary(uniqueKeysWithValues: store.images(in: .gifticon).map { ($0.id, $0.gifticon) })
    #expect(rewritten == ["oldVersion": fresh, "badDay": fresh, "valid": valid])
    #expect(try await store.gifticonExtractionPendingIDs().isEmpty)
  }

  @Test("추출 값 속성이 생기기 전에 저장한 행은 추출하지 않은 것으로 읽고 기프티콘 읽음 행만 추출 대기가 된다")
  func migratesStoreSavedBeforeGifticonState() async throws {
    let url = Self.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // 이전 빌드처럼 추출 값 열이 없는 스키마로 파일을 만들고 컨테이너를 놓은 뒤, 지금 스키마로 다시 연다.
    do {
      let container = try ModelContainer(
        for: PreGifticonSchema.StoredImage.self,
        PreGifticonSchema.StoredCategoryMembership.self,
        PreGifticonSchema.StoredTrip.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
      )
      let context = ModelContext(container)
      let encoder = PropertyListEncoder()
      let rows: [String: (category: ImageCategory, lines: Data?)] = try [
        "gifticonRead": (.gifticon, encoder.encode(Self.lines)),
        "gifticonPending": (.gifticon, nil),
        "receiptRead": (.receipt, encoder.encode(Self.lines)),
      ]
      for (id, row) in rows {
        let stored = PreGifticonSchema.StoredImage(assetID: id)
        stored.labelsData = try encoder.encode([ImageLabel]())
        stored.needsTextRecognition = true
        stored.textLinesData = row.lines
        context.insert(stored)
        stored.memberships = [PreGifticonSchema.StoredCategoryMembership(category: row.category.rawValue)]
      }
      try context.save()
    }

    let store = try PhotoStoreClientImpl(url: url)

    let images = try await store.images(ids: ["gifticonRead", "gifticonPending", "receiptRead"])
    #expect(images.count == 3)
    #expect(images.allSatisfy { $0.gifticon == nil })
    #expect(try await store.gifticonExtractionPendingIDs() == ["gifticonRead"])
    #expect(try await store.pendingTextRecognitionIDs() == ["gifticonPending"])
  }

  /// 추출 대기 판정의 후보. `pending`·`blank` 만 대기다.
  private static func pendingCandidates() throws -> [IndexedImage] {
    try [
      self.gifticon("pending", gifticon: nil),
      .stub(id: "blank", textRecognition: .recognized([]), categories: [.gifticon]),
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.gifticon]),
      .stub(id: "notNeeded", categories: [.gifticon]),
      .stub(id: "receipt", textRecognition: .recognized(self.lines), categories: [.receipt]),
      self.gifticon("notFound", gifticon: GifticonInfo(expiryDate: nil, redemptionPlace: nil)),
      self.gifticon("found", gifticon: GifticonInfo(expiryDate: self.date(2026, 12, 31), redemptionPlace: "스타벅스")),
    ]
  }

  private static func gifticon(_ id: String, gifticon: GifticonInfo?) -> IndexedImage {
    .stub(
      id: id,
      creationDate: Date(timeIntervalSince1970: 1_700_000_000),
      labels: [ImageLabel(identifier: "document", confidence: 0.4)],
      textRecognition: .recognized(self.lines),
      categories: [.gifticon, .document],
      gifticon: gifticon
    )
  }

  private static func withGifticon(_ image: IndexedImage, _ gifticon: GifticonInfo) -> IndexedImage {
    IndexedImage(
      asset: image.asset,
      labels: image.labels,
      textRecognition: image.textRecognition,
      categories: image.categories,
      gifticon: gifticon,
      // `saveGifticons` 는 보강 상태도 규칙 추출 기준으로 되돌린다.
      gifticonModelFill: .initial(for: gifticon)
    )
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
    try #require(LocalDate(year: year, month: month, day: day))
  }

  private static func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "PhotoStore.store")
  }
}

struct IndexedImageGifticonTests {
  @Test("기프티콘으로 분류돼 글자를 읽었을 때만 추출 값을 담는다")
  func keepsGifticonOnlyForRecognizedGifticon() {
    let info = GifticonInfo(expiryDate: nil, redemptionPlace: "스타벅스")

    #expect(IndexedImage.stub(id: "a", textRecognition: .recognized([]), categories: [.gifticon], gifticon: info)
      .gifticon == info)
    #expect(IndexedImage.stub(id: "b", textRecognition: .recognized([]), categories: [.receipt], gifticon: info)
      .gifticon == nil)
    #expect(IndexedImage.stub(id: "c", textRecognition: .pending, categories: [.gifticon], gifticon: info)
      .gifticon == nil)
    #expect(IndexedImage.stub(id: "d", textRecognition: .notNeeded, categories: [.gifticon], gifticon: info)
      .gifticon == nil)
  }
}
