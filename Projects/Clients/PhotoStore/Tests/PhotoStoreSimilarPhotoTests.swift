import Core
import Foundation
import PhotoStoreInterface
import Testing

/// 특징 벡터 저장·소급과 비슷한 사진 묶기 입력. Impl 과 Fake 가 같은 동작인지 같은 테스트로 본다.
struct PhotoStoreSimilarPhotoTests {
  private typealias Fixture = SimilarPhotoStoreFixture

  @Test("벡터 대상이 아닌 이미지(스크린샷·OCR 대상·생성일 없음)는 벡터를 담지 않는다")
  func normalizesNonTargets() {
    #expect(Fixture.photo("photo").featurePrint == Fixture.featurePrint(0))
    #expect(Fixture.photo("shot", isScreenshot: true).featurePrint == nil)
    #expect(Fixture.photo("undated", seconds: nil).featurePrint == nil)
    #expect(Fixture.textPhoto("pending", isRead: false).featurePrint == nil)
    #expect(Fixture.textPhoto("read", isRead: true).featurePrint == nil)
  }

  @Test("저장한 벡터를 다시 읽고, 벡터 없이 다시 저장하면 저장된 벡터를 둔다", arguments: StoreKind.allCases)
  func savesAndKeepsFeaturePrint(kind: StoreKind) async throws {
    let store = try await kind.make([Fixture.photo("a", x: 0.3)])
    defer { store.remove() }

    let resaved = Fixture.photo("a", x: nil, categories: [.food, .other])
    try await store.client.save([resaved])

    let image = try #require(try await store.client.images(ids: ["a"]).first)
    #expect(image.featurePrint == Fixture.featurePrint(0.3))
    #expect(image.categories == [.food, .other])
    #expect(try await store.client.images(in: .food).first?.featurePrint == Fixture.featurePrint(0.3))
  }

  @Test("벡터를 넘겨 다시 저장하면 바꾼다", arguments: StoreKind.allCases)
  func replacesFeaturePrint(kind: StoreKind) async throws {
    let store = try await kind.make([Fixture.photo("a", x: 0.3)])
    defer { store.remove() }

    try await store.client.save([Fixture.photo("a", x: 0.7)])

    #expect(try await store.client.images(ids: ["a"]).first?.featurePrint == Fixture.featurePrint(0.7))
  }

  @Test("벡터 대기는 벡터 없는 대상 사진이고 스크린샷·OCR 대상·생성일 없음은 빠진다", arguments: StoreKind.allCases)
  func pendingIDs(kind: StoreKind) async throws {
    let store = try await kind.make([
      Fixture.photo("pending", x: nil),
      Fixture.photo("done", x: 0),
      Fixture.photo("shot", x: nil, isScreenshot: true),
      Fixture.photo("undated", seconds: nil, x: nil),
      Fixture.textPhoto("ocrPending", isRead: false),
      Fixture.textPhoto("ocrRead", isRead: true),
    ])
    defer { store.remove() }

    #expect(try await store.client.featurePrintPendingIDs() == ["pending"])
  }

  @Test("벡터 저장은 대기 행만 바꾸고 이미 벡터가 있는 행·대상 아님·없는 식별자는 무시하며 다른 값은 그대로다", arguments: StoreKind.allCases)
  func savesFeaturePrintsOnlyForPendingRows(kind: StoreKind) async throws {
    let pending = Fixture.photo("pending", x: nil, categories: [.food, .pet])
    let store = try await kind.make([
      pending,
      Fixture.photo("done", x: 0.1),
      Fixture.textPhoto("ocr", isRead: true),
      Fixture.photo("shot", x: nil, isScreenshot: true),
    ])
    defer { store.remove() }

    try await store.client.saveFeaturePrints([
      "pending": Fixture.featurePrint(0.4),
      "done": Fixture.featurePrint(0.9),
      "ocr": Fixture.featurePrint(0.9),
      "shot": Fixture.featurePrint(0.9),
      "missing": Fixture.featurePrint(0.9),
    ])

    let images = try await store.client.images(ids: ["pending", "done", "ocr", "shot", "missing"])
    let byID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
    #expect(Set(byID.keys) == ["pending", "done", "ocr", "shot"])
    #expect(byID["pending"]?.featurePrint == Fixture.featurePrint(0.4))
    #expect(byID["pending"]?.labels == pending.labels)
    #expect(byID["pending"]?.categories == pending.categories)
    #expect(byID["done"]?.featurePrint == Fixture.featurePrint(0.1))
    #expect(byID["ocr"]?.featurePrint == nil)
    #expect(byID["shot"]?.featurePrint == nil)
    #expect(try await store.client.featurePrintPendingIDs().isEmpty)
  }

  @Test("비슷한 사진 입력은 시간 이웃이 있는 벡터 사진을 생성일 오름차순으로, 미비교 수와 함께 준다", arguments: StoreKind.allCases)
  func similarPhotoEntries(kind: StoreKind) async throws {
    let store = try await kind.make([
      Fixture.photo("c", seconds: 20, x: 0.2),
      Fixture.photo("a", seconds: 0, x: 0),
      Fixture.photo("b", seconds: 10, x: 0.1),
      Fixture.photo("alone", seconds: 5000, x: 0),
      Fixture.photo("pending1", seconds: 15, x: nil),
      Fixture.photo("pending2", seconds: 9000, x: nil),
      Fixture.photo("shot", seconds: 11, x: nil, isScreenshot: true),
      Fixture.textPhoto("ocr", seconds: 12, isRead: true),
    ])
    defer { store.remove() }

    let entries = try await store.client.similarPhotoEntries()

    #expect(entries.photos.map(\.id) == ["a", "b", "c"])
    #expect(entries.photos.map(\.featurePrint) == [0, 0.1, 0.2].map(Fixture.featurePrint))
    #expect(entries.photos.first?.asset.pixelWidth == 4032)
    #expect(entries.uncomparedCount == 2)
  }

  @Test("1단계 저장·벡터 저장·삭제가 다음 비슷한 사진 입력에 반영된다", arguments: StoreKind.allCases)
  func entriesReflectWrites(kind: StoreKind) async throws {
    let store = try await kind.make([
      Fixture.photo("a", seconds: 0, x: 0),
      Fixture.photo("b", seconds: 10, x: 0),
      Fixture.photo("c", seconds: 20, x: nil),
    ])
    defer { store.remove() }
    #expect(try await store.client.similarPhotoEntries().photos.map(\.id) == ["a", "b"])

    try await store.client.save([Fixture.photo("d", seconds: 30, x: 0)])
    #expect(try await store.client.similarPhotoEntries().photos.map(\.id) == ["a", "b", "d"])

    try await store.client.saveFeaturePrints(["c": Fixture.featurePrint(0)])
    let afterBackfill = try await store.client.similarPhotoEntries()
    #expect(afterBackfill.photos.map(\.id) == ["a", "b", "c", "d"])
    #expect(afterBackfill.uncomparedCount == 0)

    try await store.client.delete(ids: ["b"])
    #expect(try await store.client.similarPhotoEntries().photos.map(\.id) == ["a", "c", "d"])

    // 캐시에 든 사진을 벡터 없이 다시 저장해도(생성일이 바뀌어) 반영된다.
    try await store.client.save([Fixture.photo("a", seconds: 9000, x: nil)])
    #expect(try await store.client.similarPhotoEntries().photos.map(\.id) == ["c", "d"])
  }

  @Test("2단계 OCR 저장은 비슷한 사진 입력을 바꾸지 않고 미비교 수는 새로 센다", arguments: StoreKind.allCases)
  func textSaveKeepsEntries(kind: StoreKind) async throws {
    let store = try await kind.make([
      Fixture.photo("a", seconds: 0, x: 0),
      Fixture.photo("b", seconds: 10, x: 0),
      Fixture.textPhoto("ocr", seconds: 5, isRead: false),
    ])
    defer { store.remove() }
    let before = try await store.client.similarPhotoEntries()

    try await store.client.save([Fixture.textPhoto("ocr", seconds: 5, isRead: true)])

    #expect(try await store.client.similarPhotoEntries() == before)
  }

  @Test("지운 사진은 벡터 대기와 비슷한 사진 입력에서 빠진다", arguments: StoreKind.allCases)
  func deleteRemovesFeaturePrints(kind: StoreKind) async throws {
    let store = try await kind.make([
      Fixture.photo("a", seconds: 0, x: 0),
      Fixture.photo("b", seconds: 10, x: 0),
      Fixture.photo("pending", seconds: 20, x: nil),
    ])
    defer { store.remove() }

    try await store.client.delete(ids: ["a", "pending"])

    let entries = try await store.client.similarPhotoEntries()
    #expect(entries.photos.isEmpty)
    #expect(entries.uncomparedCount == 0)
    #expect(try await store.client.featurePrintPendingIDs().isEmpty)
  }
}
