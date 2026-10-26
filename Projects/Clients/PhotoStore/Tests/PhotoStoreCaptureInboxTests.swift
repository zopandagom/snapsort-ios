import Core
import Foundation
import PhotoStoreInterface
import Testing

/// 캡처 인박스 목록·보관: Impl·Fake 가 같은 표를 따른다.
struct PhotoStoreCaptureInboxTests {
  private static let since = Date(timeIntervalSince1970: 1_700_000_000)

  private static func shot(_ id: String, at offset: TimeInterval?, screenshot: Bool = true) -> IndexedImage {
    .stub(
      id: id,
      creationDate: offset.map { Self.since.addingTimeInterval($0) },
      categories: [.gifticon],
      isScreenshot: screenshot
    )
  }

  @Test("스크린샷이고 기간 안이며 보관하지 않은 것만 담는다. 경계(같은 시각)는 포함, 생성일 없음·스크린샷 아님·기간 밖은 뺀다", arguments: StoreKind.allCases)
  func conditions(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.shot("inside", at: 100),
      Self.shot("boundary", at: 0),
      Self.shot("tooOld", at: -1),
      Self.shot("noDate", at: nil),
      Self.shot("photo", at: 100, screenshot: false),
      Self.shot("kept", at: 100),
    ])
    defer { store.remove() }
    #expect(try await store.client.keepInCaptureInbox(id: "kept"))

    let assets = try await store.client.captureInboxScreenshots(createdSince: Self.since)

    #expect(Set(assets.map(\.id)) == ["inside", "boundary"])
  }

  @Test("카테고리와 관계없이 담고 메타데이터를 그대로 돌려준다", arguments: StoreKind.allCases)
  func anyCategoryAndMetadata(kind: StoreKind) async throws {
    let store = try await kind.make([
      .stub(id: "plain", creationDate: Self.since.addingTimeInterval(10), isScreenshot: true),
    ])
    defer { store.remove() }

    let assets = try await store.client.captureInboxScreenshots(createdSince: Self.since)

    #expect(assets.map(\.id) == ["plain"])
    #expect(assets.first?.isScreenshot == true)
    #expect(assets.first?.pixelWidth == 1170)
    #expect(assets.first?.creationDate == Self.since.addingTimeInterval(10))
  }

  @Test("최신순이고 생성일이 같으면 식별자 순이다", arguments: StoreKind.allCases)
  func newestFirst(kind: StoreKind) async throws {
    let store = try await kind.make([
      Self.shot("old", at: 10),
      Self.shot("b", at: 50),
      Self.shot("a", at: 50),
      Self.shot("new", at: 90),
    ])
    defer { store.remove() }

    let assets = try await store.client.captureInboxScreenshots(createdSince: Self.since)

    #expect(assets.map(\.id) == ["new", "a", "b", "old"])
  }

  @Test("보관하면 목록에서 빠지고 없는 행은 false 다. 다른 값은 그대로다", arguments: StoreKind.allCases)
  func keep(kind: StoreKind) async throws {
    let image = Self.shot("a", at: 10)
    let store = try await kind.make([image, Self.shot("b", at: 20)])
    defer { store.remove() }

    #expect(try await store.client.keepInCaptureInbox(id: "a"))
    #expect(try await store.client.keepInCaptureInbox(id: "missing") == false)

    #expect(try await store.client.captureInboxScreenshots(createdSince: Self.since).map(\.id) == ["b"])
    #expect(try await store.client.images(ids: ["a"]) == [image])
  }

  @Test("같은 행을 다시 저장해도 보관은 유지된다", arguments: StoreKind.allCases)
  func saveKeepsKeptState(kind: StoreKind) async throws {
    let store = try await kind.make([Self.shot("a", at: 10)])
    defer { store.remove() }
    _ = try await store.client.keepInCaptureInbox(id: "a")

    try await store.client.save([Self.shot("a", at: 10)])

    #expect(try await store.client.captureInboxScreenshots(createdSince: Self.since).isEmpty)
  }

  @Test("행을 지운 뒤 같은 식별자로 다시 저장하면 보관하지 않은 것으로 돌아온다", arguments: StoreKind.allCases)
  func deleteResetsKeptState(kind: StoreKind) async throws {
    let store = try await kind.make([Self.shot("a", at: 10)])
    defer { store.remove() }
    _ = try await store.client.keepInCaptureInbox(id: "a")

    try await store.client.delete(ids: ["a"])
    try await store.client.save([Self.shot("a", at: 10)])

    #expect(try await store.client.captureInboxScreenshots(createdSince: Self.since).map(\.id) == ["a"])
  }

  @Test("빈 저장소는 빈 목록이다", arguments: StoreKind.allCases)
  func empty(kind: StoreKind) async throws {
    let store = try await kind.make([])
    defer { store.remove() }

    #expect(try await store.client.captureInboxScreenshots(createdSince: Self.since).isEmpty)
  }
}
