import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import Testing

/// 검색 목록 읽기: Impl·Fake 가 같은 표를 따른다. 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct PhotoStoreSearchTests {
  private static func lines(_ texts: [String]) -> [RecognizedTextLine] {
    texts.map { RecognizedTextLine(text: $0, confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)) }
  }

  private static func read(
    _ id: String,
    _ texts: [String],
    created: TimeInterval? = 1_700_000_000,
    categories: Set<ImageCategory> = [],
    groups: CaptureGroups? = nil
  ) -> IndexedImage {
    .stub(
      id: id,
      creationDate: created.map { Date(timeIntervalSince1970: $0) },
      textRecognition: .recognized(self.lines(texts)),
      categories: categories,
      captureGroups: groups
    )
  }

  @Test("글자를 읽은 이미지만 담고 OCR 대기·대상 아님은 뺀다. 대기 수는 대기만 센다", arguments: StoreKind.allCases)
  func onlyRecognizedImages(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.read("read", ["가나다"]),
      Self.read("blank", []),
      .stub(id: "pending", textRecognition: .pending),
      .stub(id: "pending2", textRecognition: .pending, categories: [.shopping]),
      .stub(id: "notNeeded"),
    ])
    defer { store.remove() }

    let result = try await store.client.searchEntries()

    #expect(Set(result.entries.map(\.id)) == ["read", "blank"])
    #expect(result.pendingTextCount == 2)
  }

  @Test("줄 원문을 읽은 순서로 담고 메타데이터를 그대로 담는다", arguments: StoreKind.allCases)
  func linesAndAsset(kind: StoreKind) async throws {
    let image = IndexedImage.stub(
      id: "a",
      creationDate: Date(timeIntervalSince1970: 1_700_000_000),
      coordinate: Coordinate(latitude: 37.5, longitude: 127.0),
      textRecognition: .recognized(Self.lines(["둘째 줄 B", "첫째  줄", "셋째"]))
    )
    let store = try await kind.make([image])
    defer { store.remove() }

    let entry = try #require(try await store.client.searchEntries().entries.first)

    #expect(entry.lines == ["둘째 줄 B", "첫째  줄", "셋째"])
    #expect(entry.asset == image.asset)
    #expect(entry.captureGroups == nil)
  }

  @Test("최신순이고 생성일이 없으면 뒤, 같으면 식별자 순이다", arguments: StoreKind.allCases)
  func newestFirst(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.read("old", ["x"], created: 100),
      Self.read("noDateB", ["x"], created: nil),
      Self.read("newB", ["x"], created: 300),
      Self.read("newA", ["x"], created: 300),
      Self.read("noDateA", ["x"], created: nil),
      Self.read("mid", ["x"], created: 200),
    ])
    defer { store.remove() }

    #expect(try await store.client.searchEntries().entries.map(\.id) == [
      "newA", "newB", "mid", "old", "noDateA", "noDateB",
    ])
  }

  @Test("캡처 묶음 값은 있으면 담고 추출 전이면 nil 이다. 줄은 어느 쪽이든 담는다", arguments: StoreKind.allCases)
  func captureGroups(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.read("shopping", ["주문"], categories: [.shopping], groups: CaptureGroupStoreFixture.shopping),
      Self.read("map", ["지도"], categories: [.map], groups: CaptureGroupStoreFixture.map),
      Self.read("notExtracted", ["미추출"], categories: [.shopping], groups: nil),
      Self.read("empty", ["빈값"], categories: [.chat], groups: .empty),
    ])
    defer { store.remove() }

    let byID = try await Dictionary(
      uniqueKeysWithValues: store.client.searchEntries().entries.map { ($0.id, $0) }
    )

    #expect(byID["shopping"]?.captureGroups == CaptureGroupStoreFixture.shopping)
    #expect(byID["map"]?.captureGroups == CaptureGroupStoreFixture.map)
    #expect(byID["notExtracted"]?.captureGroups == nil)
    #expect(byID["notExtracted"]?.lines == ["미추출"])
    #expect(byID["empty"]?.captureGroups == .empty)
  }

  @Test("빈 저장소는 빈 목록과 대기 0 이다", arguments: StoreKind.allCases)
  func emptyStore(kind: StoreKind) async throws {
    let store = try await kind.make([])
    defer { store.remove() }

    #expect(try await store.client.searchEntries() == SearchEntries(entries: [], pendingTextCount: 0))
  }

  @Test("저장·삭제 뒤 다시 읽으면 바뀐 값을 준다", arguments: StoreKind.allCases)
  func reflectsChanges(kind: StoreKind) async throws {
    let store = try await kind.make([Self.read("a", ["하나"]), .stub(id: "p", textRecognition: .pending)])
    defer { store.remove() }
    #expect(try await store.client.searchEntries().pendingTextCount == 1)

    try await store.client.save([Self.read("p", ["읽음"])])
    try await store.client.delete(ids: ["a"])

    let result = try await store.client.searchEntries()
    #expect(result.entries.map(\.id) == ["p"])
    #expect(result.entries.first?.lines == ["읽음"])
    #expect(result.pendingTextCount == 0)
  }
}
