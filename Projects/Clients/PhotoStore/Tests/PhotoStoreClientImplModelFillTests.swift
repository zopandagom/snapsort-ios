import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

struct PhotoStoreClientImplModelFillTests {
  @Test("보강 상태를 저장하고 읽는다")
  func roundTripsModelFillStates() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let partial = try Fixture.partial()
    let images = [
      Fixture.gifticon("done", gifticon: partial, fill: .done),
      Fixture.gifticon("pending", gifticon: partial, fill: .pending(failures: 0)),
      Fixture.gifticon("failedTwice", gifticon: partial, fill: .pending(failures: 2)),
      // 추출 값이 없으면 init 이 보강하지 않음으로 둔다.
      Fixture.gifticon("notExtracted", gifticon: nil, fill: .done),
    ]

    try await store.save(images)

    let read = try await Fixture.fills(store)
    #expect(read == [
      "done": .done,
      "pending": .pending(failures: 0),
      "failedTwice": .pending(failures: 2),
      "notExtracted": .pending(failures: 0),
    ])
    #expect(try await Set(store.images(ids: Set(images.map(\.id)))) == Set(images))

    // 인덱서는 다른 보강 버전을 쓰지 않는다. 넘어오면 보강하지 않음으로 쓴다(방어).
    try await store.save([Fixture.gifticon("done", gifticon: partial, fill: .stale)])
    #expect(try await Fixture.fills(store)["done"] == .pending(failures: 0))
  }

  @Test("규칙만으로 두 값을 찾아 저장하면 보강을 마친 것으로 쓴다")
  func marksRuleOnlyCompleteGifticonAsDone() async throws {
    let complete = try Fixture.complete()
    let partial = try Fixture.partial()
    #expect(GifticonModelFill.initial(for: complete) == .done)
    #expect(GifticonModelFill.initial(for: partial) == .pending(failures: 0))
    #expect(GifticonModelFill
      .initial(for: GifticonInfo(expiryDate: nil, redemptionPlace: "CU")) == .pending(failures: 0))
    #expect(GifticonModelFill.initial(for: nil) == .pending(failures: 0))

    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      Fixture.gifticon("saved", gifticon: complete, fill: .initial(for: complete)),
      Fixture.gifticon("completeLater", gifticon: nil),
      Fixture.gifticon("partialLater", gifticon: nil),
    ])
    try await store.saveGifticons(["completeLater": complete, "partialLater": partial])

    #expect(try await Fixture.fills(store) == [
      "saved": .done,
      "completeLater": .done,
      "partialLater": .pending(failures: 0),
    ])
    #expect(try await store.gifticonModelFillPendingIDs() == ["partialLater"])
  }

  @Test("보강 대기는 지금 규칙 버전으로 추출했고 보강을 마치지 않은 기프티콘이다")
  func listsModelFillPending() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save(Fixture.pendingCandidates())

    let pending = try await store.gifticonModelFillPendingIDs()
    #expect(pending == ["pending", "failedOnce", "complete"])
    #expect(try await pending.isDisjoint(with: store.gifticonExtractionPendingIDs()))
    // 보강 대기는 알림 동기화를 막지 않는다: 지금 값의 만료일이 만료 예정에 든다.
    #expect(try await store.upcomingGifticonExpiries(from: Fixture.date(2026, 1, 1)).map(\.imageID).sorted()
      == ["complete", "done", "failedOnce", "pending"])
  }

  @Test("보강 결과는 보강 대기 행에만 저장한다")
  func savesModelFillsOnlyForPendingRows() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let candidates = Fixture.pendingCandidates()
    try await store.save(candidates)
    let filled = try GifticonInfo(expiryDate: Fixture.date(2027, 3, 1), redemptionPlace: "배스킨라빈스")

    try await store.saveGifticonModelFills(Dictionary(
      uniqueKeysWithValues: (candidates.map(\.id) + ["missing"]).map { ($0, .filled(filled)) }
    ))

    let stored = try await Dictionary(
      uniqueKeysWithValues: store.images(ids: Set(candidates.map(\.id))).map { ($0.id, $0) }
    )
    let expected = Dictionary(uniqueKeysWithValues: candidates.map { image in
      let isPending = ["pending", "failedOnce", "complete"].contains(image.id)
      return (image.id, isPending ? Fixture.with(image, gifticon: filled, fill: .done) : image)
    })
    #expect(stored == expected)
    #expect(try await store.indexedIDs() == Set(candidates.map(\.id)))
    #expect(try await store.gifticonModelFillPendingIDs().isEmpty)
    #expect(try await store.gifticonExtractionPendingIDs() == ["notExtracted"])
  }

  @Test("실패는 규칙 값으로 바꾸고 한도까지 세며 한도에서 마친 것으로 둔다")
  func countsFailuresUpToLimit() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let modelValue = try GifticonInfo(expiryDate: Fixture.date(2027, 1, 31), redemptionPlace: "스타벅스")
    try await store.save([Fixture.gifticon("a", gifticon: modelValue, fill: .pending(failures: 0))])
    let rules = try Fixture.partial()

    for failures in 1 ..< GifticonModelFill.maximumFailures {
      try await store.saveGifticonModelFills(["a": .failed(rules: rules)])
      let image = try #require(try await store.images(ids: ["a"]).first)
      #expect(image.gifticon == rules)
      #expect(image.gifticonModelFill == .pending(failures: failures))
      #expect(try await store.gifticonModelFillPendingIDs() == ["a"])
    }

    try await store.saveGifticonModelFills(["a": .failed(rules: rules)])
    let image = try #require(try await store.images(ids: ["a"]).first)
    #expect(image.gifticon == rules)
    #expect(image.gifticonModelFill == .done)
    #expect(try await store.gifticonModelFillPendingIDs().isEmpty)
  }

  @Test("보강 버전이 다르면 두 값이 있어도 stale 로 읽고 보강 대기에 든다")
  func readsOtherModelVersionAsStale() async throws {
    let url = Fixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let current = GifticonExtractor.modelFillVersion
    try Fixture.writeRows(at: url, [
      "older": (modelVersion: current + 1, failures: 2),
      "current": (modelVersion: current, failures: 0),
      "unfilled": (modelVersion: 0, failures: 1),
    ])
    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await Fixture.fills(store) == [
      "older": .stale,
      "current": .done,
      "unfilled": .pending(failures: 1),
    ])
    #expect(try await store.gifticonModelFillPendingIDs() == ["older", "unfilled"])
    // 되돌리기 전까지 옛 값으로 만료 예정에 든다(알림 동기화를 막지 않는다).
    #expect(try await store.upcomingGifticonExpiries(from: Fixture.date(2026, 1, 1)).map(\.imageID).sorted()
      == ["current", "older", "unfilled"])

    // 다른 보강 버전에서 센 실패 수는 없으므로 실패는 1 부터 센다.
    let rules = GifticonInfo(expiryDate: nil, redemptionPlace: nil)
    try await store.saveGifticonModelFills(["older": .failed(rules: rules)])
    let image = try #require(try await store.images(ids: ["older"]).first)
    #expect(image.gifticon == rules)
    #expect(image.gifticonModelFill == .pending(failures: 1))
    #expect(try await store.upcomingGifticonExpiries(from: Fixture.date(2026, 1, 1)).map(\.imageID).sorted()
      == ["current", "unfilled"])
  }

  @Test("deferred 는 규칙 값으로 바꾸고 보강하지 않은 상태로 둔다")
  func defersWithRuleValues() async throws {
    let url = Fixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Fixture.writeRows(at: url, [
      "older": (modelVersion: GifticonExtractor.modelFillVersion + 1, failures: 2),
      "failedTwice": (modelVersion: 0, failures: 2),
    ])
    let store = try PhotoStoreClientImpl(url: url)
    let rules = try Fixture.partial()

    try await store.saveGifticonModelFills(["older": .deferred(rules: rules), "failedTwice": .deferred(rules: rules)])

    let images = try await Dictionary(
      uniqueKeysWithValues: store.images(in: .gifticon).map { ($0.id, ($0.gifticon, $0.gifticonModelFill)) }
    )
    #expect(images["older"]?.0 == rules)
    #expect(images["older"]?.1 == .pending(failures: 0))
    #expect(images["failedTwice"]?.0 == rules)
    #expect(images["failedTwice"]?.1 == .pending(failures: 2))
    #expect(try await store.gifticonModelFillPendingIDs() == ["older", "failedTwice"])
  }

  @Test("규칙으로 다시 추출하면 보강 대기로 돌아간다")
  func resetsModelFillOnRuleExtraction() async throws {
    let url = Fixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    // 보강을 마쳤는데 규칙 버전이 바뀌어 추출 대기가 된 행.
    try Fixture.writeRows(
      at: url,
      ["a": (modelVersion: GifticonExtractor.modelFillVersion, failures: 0)],
      rulesVersion: GifticonExtractor.rulesVersion + 1
    )
    let store = try PhotoStoreClientImpl(url: url)
    #expect(try await store.gifticonExtractionPendingIDs() == ["a"])
    #expect(try await store.gifticonModelFillPendingIDs().isEmpty)
    // 추출 대기 행에는 보강 결과가 붙지 않는다.
    try await store.saveGifticonModelFills(["a": .filled(Fixture.complete())])
    #expect(try await store.gifticonExtractionPendingIDs() == ["a"])

    let rules = try Fixture.partial()
    try await store.saveGifticons(["a": rules])

    let image = try #require(try await store.images(ids: ["a"]).first)
    #expect(image.gifticon == rules)
    #expect(image.gifticonModelFill == .pending(failures: 0))
    #expect(try await store.gifticonModelFillPendingIDs() == ["a"])
  }

  @Test("보강 속성 전 저장 파일이 경량 이전으로 열리고 보강 대기로 읽힌다")
  func migratesStoreSavedBeforeModelFillState() async throws {
    let url = Fixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // 이전 빌드처럼 보강 열이 없는 스키마로 파일을 만들고 컨테이너를 놓은 뒤, 지금 스키마로 다시 연다.
    do {
      let container = try ModelContainer(
        for: PreModelFillSchema.StoredImage.self,
        PreModelFillSchema.StoredCategoryMembership.self,
        PreModelFillSchema.StoredTrip.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
      )
      let context = ModelContext(container)
      let encoder = PropertyListEncoder()
      let categories: [String: ImageCategory] = [
        "complete": .gifticon, "partial": .gifticon, "notExtracted": .gifticon, "receipt": .receipt,
      ]
      // 지금 규칙 버전으로 추출한 행의 교환처. 만료일은 모두 2026-12-31 이다.
      let extracted: [String: String?] = ["complete": "스타벅스", "partial": nil]
      for (id, category) in categories {
        let stored = PreModelFillSchema.StoredImage(assetID: id)
        stored.labelsData = try encoder.encode([ImageLabel]())
        stored.needsTextRecognition = true
        stored.textLinesData = try encoder.encode(Fixture.lines)
        if let place = extracted[id] {
          stored.gifticonRulesVersion = GifticonExtractor.rulesVersion
          stored.gifticonExpiryDay = 20_261_231
          stored.gifticonRedemptionPlace = place
        }
        context.insert(stored)
        stored.memberships = [PreModelFillSchema.StoredCategoryMembership(category: category.rawValue)]
      }
      try context.save()
    }

    let store = try PhotoStoreClientImpl(url: url)

    let images = try await store.images(ids: ["complete", "partial", "notExtracted", "receipt"])
    #expect(images.count == 4)
    #expect(images.allSatisfy { $0.gifticonModelFill == .pending(failures: 0) })
    // 이전 값은 모두 규칙 값이라 보강하지 않음으로 읽는다. 두 값이 있는 행도 소급이 모델 없이 마친다.
    #expect(try await store.gifticonModelFillPendingIDs() == ["complete", "partial"])
    #expect(try await store.gifticonExtractionPendingIDs() == ["notExtracted"])
    #expect(try await store.images(ids: ["complete"]).first?.gifticon
      == GifticonInfo(expiryDate: Fixture.date(2026, 12, 31), redemptionPlace: "스타벅스"))
  }
}

/// 보강 테스트의 저장소·이미지 준비.
private enum Fixture {
  static let lines = [
    RecognizedTextLine(
      text: "유효기간 2026.12.31",
      confidence: 0.9,
      boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)
    ),
  ]

  /// 보강 대기 판정의 후보. `pending`·`failedOnce`·`complete` 만 대기다.
  static func pendingCandidates() -> [IndexedImage] {
    let partial = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let complete = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "스타벅스")
    return [
      self.gifticon("pending", gifticon: partial, fill: .pending(failures: 0)),
      self.gifticon("failedOnce", gifticon: partial, fill: .pending(failures: 1)),
      // 저장소는 값 출처를 모르므로 두 값이 있어도 보강하지 않음이면 대기다.
      self.gifticon("complete", gifticon: complete, fill: .pending(failures: 0)),
      self.gifticon("done", gifticon: partial, fill: .done),
      self.gifticon("notExtracted", gifticon: nil),
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.gifticon]),
      .stub(id: "receipt", textRecognition: .recognized(self.lines), categories: [.receipt]),
    ]
  }

  /// 저장소가 쓰지 않는 보강 버전·규칙 버전을 직접 넣기 위해 Impl 스키마로 기프티콘 읽음 행을 만들고 컨테이너를 놓는다.
  /// 행마다 만료일 2026-12-31·교환처 "스타벅스" 를 둔다.
  static func writeRows(
    at url: URL,
    _ rows: [String: (modelVersion: Int, failures: Int)],
    rulesVersion: Int = GifticonExtractor.rulesVersion
  ) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    for (id, row) in rows {
      let stored = StoredImage(assetID: id)
      stored.labelsData = try encoder.encode([ImageLabel]())
      stored.needsTextRecognition = true
      stored.textLinesData = try encoder.encode(self.lines)
      stored.gifticonRulesVersion = rulesVersion
      stored.gifticonExpiryDay = 20_261_231
      stored.gifticonRedemptionPlace = "스타벅스"
      stored.gifticonModelVersion = row.modelVersion
      stored.gifticonModelFailures = row.failures
      context.insert(stored)
      stored.memberships = [StoredCategoryMembership(category: ImageCategory.gifticon.rawValue)]
    }
    try context.save()
  }

  static func fills(_ store: PhotoStoreClientImpl) async throws -> [ImageAsset.ID: GifticonModelFill] {
    try await Dictionary(uniqueKeysWithValues: store.images(in: .gifticon).map { ($0.id, $0.gifticonModelFill) })
  }

  static func gifticon(
    _ id: String,
    gifticon: GifticonInfo?,
    fill: GifticonModelFill = .pending(failures: 0)
  ) -> IndexedImage {
    .stub(
      id: id,
      creationDate: Date(timeIntervalSince1970: 1_700_000_000),
      labels: [ImageLabel(identifier: "document", confidence: 0.4)],
      textRecognition: .recognized(self.lines),
      categories: [.gifticon, .document],
      gifticon: gifticon,
      gifticonModelFill: fill
    )
  }

  static func with(_ image: IndexedImage, gifticon: GifticonInfo, fill: GifticonModelFill) -> IndexedImage {
    IndexedImage(
      asset: image.asset,
      labels: image.labels,
      textRecognition: image.textRecognition,
      categories: image.categories,
      gifticon: gifticon,
      gifticonModelFill: fill
    )
  }

  static func partial() throws -> GifticonInfo {
    try GifticonInfo(expiryDate: self.date(2026, 12, 31), redemptionPlace: nil)
  }

  static func complete() throws -> GifticonInfo {
    try GifticonInfo(expiryDate: self.date(2026, 12, 31), redemptionPlace: "스타벅스")
  }

  static func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
    try #require(LocalDate(year: year, month: month, day: day))
  }

  static func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "PhotoStore.store")
  }
}

struct IndexedImageModelFillTests {
  @Test("추출 값이 없으면 보강 상태를 보강하지 않음으로 두고, 있으면 넘긴 상태를 그대로 둔다")
  func normalizesModelFillOnlyWithoutGifticon() {
    let info = GifticonInfo(expiryDate: nil, redemptionPlace: "스타벅스")

    #expect(IndexedImage.stub(
      id: "a",
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: info,
      gifticonModelFill: .stale
    ).gifticonModelFill == .stale)
    #expect(IndexedImage.stub(
      id: "b",
      textRecognition: .recognized([]),
      categories: [.receipt],
      gifticon: info,
      gifticonModelFill: .done
    ).gifticonModelFill == .pending(failures: 0))
    #expect(IndexedImage.stub(id: "c", textRecognition: .pending, categories: [.gifticon], gifticonModelFill: .done)
      .gifticonModelFill == .pending(failures: 0))
  }
}
