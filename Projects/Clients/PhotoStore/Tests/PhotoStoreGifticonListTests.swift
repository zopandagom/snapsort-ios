import Core
import Foundation
import PhotoStoreInterface
import Testing

/// 기프티콘 목록·사용 여부·필드별 출처. Impl 과 Fake 가 같은 동작인지 같은 테스트로 본다.
/// 교환처와 OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct PhotoStoreGifticonListTests {
  @Test("사용 여부는 기프티콘 행에만 쓰고 목록·한 장 읽기에 반영한다", arguments: StoreKind.allCases)
  func setsUsageOnlyOnGifticons(kind: StoreKind) async throws {
    let store = try await kind.make([GifticonListFixture.gifticon("a"), GifticonListFixture.receipt("r")])
    defer { store.remove() }

    #expect(try await store.client.setGifticonUsed(true, id: "a"))
    #expect(try await store.client.setGifticonUsed(true, id: "r") == false)
    #expect(try await store.client.setGifticonUsed(true, id: "missing") == false)

    #expect(try await store.client.gifticons().map { [$0.id: $0.isUsed] } == [["a": true]])
    #expect(try await store.client.gifticon(id: "a")?.isUsed == true)
    #expect(try await store.client.setGifticonUsed(false, id: "a"))
    #expect(try await store.client.gifticon(id: "a")?.isUsed == false)
  }

  @Test("같은 행을 다시 저장하면 기프티콘이면 사용 여부를 두고, 빠지면 지우며, 다시 기프티콘이 돼도 미사용이다", arguments: StoreKind.allCases)
  func keepsUsageAcrossResaveUntilLeavingGifticon(kind: StoreKind) async throws {
    let store = try await kind.make([GifticonListFixture.gifticon("a")], usedIDs: ["a"])
    defer { store.remove() }

    try await store.client.save([GifticonListFixture.gifticon("a", info: GifticonListFixture.partial)])
    #expect(try await store.client.gifticon(id: "a")?.isUsed == true)

    try await store.client.save([GifticonListFixture.receipt("a")])
    #expect(try await store.client.gifticon(id: "a") == nil)

    try await store.client.save([GifticonListFixture.gifticon("a")])
    #expect(try await store.client.gifticon(id: "a")?.isUsed == false)
  }

  @Test("소급 추출·보강 결과 저장은 사용 여부를 건드리지 않는다", arguments: StoreKind.allCases)
  func keepsUsageAcrossExtractionAndModelFill(kind: StoreKind) async throws {
    let store = try await kind.make(
      [
        GifticonListFixture.gifticon("extracting", info: nil),
        GifticonListFixture.gifticon("filling", info: GifticonListFixture.partial, fill: .pending(failures: 0)),
      ],
      usedIDs: ["extracting", "filling"]
    )
    defer { store.remove() }

    try await store.client.saveGifticons(["extracting": GifticonListFixture.complete])
    try await store.client.saveGifticonModelFills(["filling": .filled(GifticonListFixture.complete)])

    let items = try await store.client.gifticons()
    #expect(items.map(\.id).sorted() == ["extracting", "filling"])
    let allUsed = items.allSatisfy(\.isUsed)
    #expect(allUsed)
    #expect(items.allSatisfy { $0.status == .extracted(GifticonListFixture.complete) })
  }

  @Test("지운 뒤 다시 저장하면 미사용이다", arguments: StoreKind.allCases)
  func forgetsUsageAfterDelete(kind: StoreKind) async throws {
    let store = try await kind.make([GifticonListFixture.gifticon("a")], usedIDs: ["a"])
    defer { store.remove() }

    try await store.client.delete(ids: ["a"])
    #expect(try await store.client.gifticon(id: "a") == nil)
    try await store.client.save([GifticonListFixture.gifticon("a")])

    #expect(try await store.client.gifticon(id: "a")?.isUsed == false)
  }

  @Test("사용한 기프티콘은 만료 예정에서 빠지고 되돌리면 다시 든다", arguments: StoreKind.allCases)
  func excludesUsedFromUpcomingExpiries(kind: StoreKind) async throws {
    let store = try await kind.make([GifticonListFixture.gifticon("a"), GifticonListFixture.gifticon("b")])
    defer { store.remove() }
    let from = try GifticonListFixture.date(2026, 1, 1)

    _ = try await store.client.setGifticonUsed(true, id: "a")
    #expect(try await store.client.upcomingGifticonExpiries(from: from).map(\.imageID) == ["b"])

    _ = try await store.client.setGifticonUsed(false, id: "a")
    #expect(try await store.client.upcomingGifticonExpiries(from: from).map(\.imageID) == ["a", "b"])
  }

  @Test("2단계 저장의 필드별 출처를 식별자 읽기·목록에서 그대로 읽는다", arguments: StoreKind.allCases)
  func roundTripsModelFilledFields(kind: StoreKind) async throws {
    let filled = try GifticonInfo(
      expiryDate: GifticonListFixture.date(2026, 12, 31),
      redemptionPlace: "스타벅스",
      modelFilledFields: [.expiryDate]
    )
    let store = try await kind.make([GifticonListFixture.gifticon("a", info: filled, fill: .done)])
    defer { store.remove() }

    #expect(try await store.client.images(ids: ["a"]).first?.gifticon?.modelFilledFields == [.expiryDate])
    let item = try #require(try await store.client.gifticon(id: "a"))
    #expect(item.status == .extracted(filled))
    #expect(item.estimatedFields == [.expiryDate])
  }

  @Test("보강 결과는 넘긴 출처로 쓰고, 규칙 값 결과·소급 추출은 규칙(빈 출처)으로 덮는다", arguments: StoreKind.allCases)
  func writesSourcesFromResults(kind: StoreKind) async throws {
    let modelPlace = try GifticonInfo(
      expiryDate: GifticonListFixture.date(2026, 12, 31),
      redemptionPlace: "CU",
      modelFilledFields: [.redemptionPlace]
    )
    // 2단계에서 모델 값이 붙었지만 보강 대기로 남은 행(시스템이 거부한 뒤 등).
    let pendingWithModelValue = GifticonListFixture.gifticon("failed", info: modelPlace, fill: .pending(failures: 0))
    let store = try await kind.make([
      GifticonListFixture.gifticon("filled", info: GifticonListFixture.partial, fill: .pending(failures: 0)),
      pendingWithModelValue,
      GifticonListFixture.gifticon("deferred", info: modelPlace, fill: .pending(failures: 0)),
      GifticonListFixture.gifticon("extracted", info: nil),
    ])
    defer { store.remove() }

    try await store.client.saveGifticonModelFills([
      "filled": .filled(modelPlace),
      "failed": .failed(rules: GifticonListFixture.partial),
      "deferred": .deferred(rules: GifticonListFixture.partial),
    ])
    try await store.client.saveGifticons(["extracted": GifticonListFixture.complete])

    let sources = try await Dictionary(uniqueKeysWithValues: store.client.images(
      ids: ["filled", "failed", "deferred", "extracted"]
    ).map { ($0.id, $0.gifticon?.modelFilledFields) })
    #expect(sources == ["filled": [.redemptionPlace], "failed": [], "deferred": [], "extracted": []])
  }

  @Test("기프티콘 목록은 최신순이고 상태는 추출 값·OCR 상태로 정한다", arguments: StoreKind.allCases)
  func listsGifticonsNewestFirstWithStatus(kind: StoreKind) async throws {
    let store = try await kind.make([
      GifticonListFixture.gifticon("undatedB", info: GifticonListFixture.partial, created: nil),
      GifticonListFixture.gifticon("extracted", info: GifticonListFixture.partial, created: 300),
      .stub(
        id: "ocrPending",
        creationDate: Date(timeIntervalSince1970: 200),
        textRecognition: .pending,
        categories: [.gifticon]
      ),
      GifticonListFixture.gifticon("extractionPending", info: nil, created: 100),
      .stub(id: "undatedA", textRecognition: .notNeeded, categories: [.gifticon, .shopping]),
      GifticonListFixture.receipt("receipt"),
    ])
    defer { store.remove() }

    let items = try await store.client.gifticons()

    #expect(items.map(\.id) == ["extracted", "ocrPending", "extractionPending", "undatedA", "undatedB"])
    #expect(items.map(\.status) == [
      .extracted(GifticonListFixture.partial),
      .checking,
      .checking,
      // 글자를 읽지 않는 기프티콘은 찾을 값이 없다.
      .extracted(GifticonInfo(expiryDate: nil, redemptionPlace: nil)),
      .extracted(GifticonListFixture.partial),
    ])
    #expect(items.allSatisfy { !$0.isUsed && $0.estimatedFields.isEmpty })
  }

  @Test("한 장 읽기는 기프티콘이 아니거나 없으면 nil 이다", arguments: StoreKind.allCases)
  func readsOneGifticon(kind: StoreKind) async throws {
    let store = try await kind.make([GifticonListFixture.gifticon("a"), GifticonListFixture.receipt("r")])
    defer { store.remove() }

    #expect(try await store.client.gifticon(id: "a")?.status == .extracted(GifticonListFixture.complete))
    #expect(try await store.client.gifticon(id: "r") == nil)
    #expect(try await store.client.gifticon(id: "missing") == nil)
  }

  @Test("출처를 모르는 행·다른 보강 버전 행은 값이 있는 필드가 모두 추정이다", arguments: StoreKind.allCases)
  func estimatesValuesOfUnknownSources(kind: StoreKind) async throws {
    let store = try await kind.make([
      GifticonListFixture.gifticon("sourcesUnknown", info: GifticonListFixture.complete, fill: .sourcesUnknown),
      GifticonListFixture.gifticon("stale", info: GifticonListFixture.partial, fill: .stale),
      GifticonListFixture.gifticon("done", info: GifticonListFixture.complete, fill: .done),
    ])
    defer { store.remove() }

    let estimated = try await Dictionary(
      uniqueKeysWithValues: store.client.gifticons().map { ($0.id, $0.estimatedFields) }
    )

    #expect(estimated == ["sourcesUnknown": [.expiryDate, .redemptionPlace], "stale": [.expiryDate], "done": []])
  }

  @Test("출처를 모르는 마침 행은 값 그대로 만료 예정·보강 대기에 든다", arguments: StoreKind.allCases)
  func keepsSourcesUnknownRowsInExpiriesAndModelFill(kind: StoreKind) async throws {
    let store = try await kind.make([
      GifticonListFixture.gifticon("sourcesUnknown", info: GifticonListFixture.complete, fill: .sourcesUnknown),
      GifticonListFixture.gifticon("done", info: GifticonListFixture.complete, fill: .done),
    ])
    defer { store.remove() }

    let image = try #require(try await store.client.images(ids: ["sourcesUnknown"]).first)
    #expect(image.gifticonModelFill == .sourcesUnknown)
    #expect(image.gifticon == GifticonListFixture.complete)
    #expect(try await store.client.gifticonModelFillPendingIDs() == ["sourcesUnknown"])
    #expect(try await store.client.upcomingGifticonExpiries(from: GifticonListFixture.date(2026, 1, 1)).map(\.imageID)
      == ["done", "sourcesUnknown"])
  }

  @Test("출처 판정은 행이 출처를 모르고 저장된 두 값이 같을 때만 출처를 써서 마친다", arguments: StoreKind.allCases)
  func resolvesSourcesOnlyWhenUnchanged(kind: StoreKind) async throws {
    let store = try await kind.make([
      GifticonListFixture.gifticon("resolved", info: GifticonListFixture.complete, fill: .sourcesUnknown),
      GifticonListFixture.gifticon("changed", info: GifticonListFixture.complete, fill: .sourcesUnknown),
      GifticonListFixture.gifticon("pending", info: GifticonListFixture.complete, fill: .pending(failures: 1)),
    ])
    defer { store.remove() }
    let resolved = try GifticonInfo(
      expiryDate: GifticonListFixture.date(2026, 12, 31),
      redemptionPlace: "스타벅스",
      modelFilledFields: [.redemptionPlace]
    )
    let otherValue = try GifticonInfo(
      expiryDate: GifticonListFixture.date(2027, 1, 31),
      redemptionPlace: "스타벅스",
      modelFilledFields: [.expiryDate]
    )

    try await store.client.saveGifticonModelFills([
      "resolved": .resolvedSources(resolved),
      "changed": .resolvedSources(otherValue),
      "pending": .resolvedSources(resolved),
    ])

    let images = try await Dictionary(uniqueKeysWithValues: store.client.images(
      ids: ["resolved", "changed", "pending"]
    ).map { ($0.id, $0) })
    #expect(images["resolved"]?.gifticon == resolved)
    #expect(images["resolved"]?.gifticonModelFill == .done)
    #expect(images["changed"]?.gifticon == GifticonListFixture.complete)
    #expect(images["changed"]?.gifticonModelFill == .sourcesUnknown)
    #expect(images["pending"]?.gifticon == GifticonListFixture.complete)
    #expect(images["pending"]?.gifticonModelFill == .pending(failures: 1))
    #expect(try await store.client.gifticon(id: "resolved")?.estimatedFields == [.redemptionPlace])
    #expect(try await store.client.gifticonModelFillPendingIDs() == ["changed", "pending"])
  }
}
