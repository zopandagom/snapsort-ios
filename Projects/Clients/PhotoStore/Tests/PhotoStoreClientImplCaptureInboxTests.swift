import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// Impl 만의 최근 스크린샷 동작: 경량 이전. 같은 동작은 `PhotoStoreCaptureInboxTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplCaptureInboxTests {
  private static let created = Date(timeIntervalSince1970: 1_700_000_000)

  @Test("보관 속성 전 저장 파일이 경량 이전으로 열리고, 기존 행은 보관하지 않음이며 기존 값은 그대로다")
  func migratesStoreSavedBeforeCaptureInbox() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writePreCaptureInboxRows(at: url)

    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.indexedIDs() == ["shot", "photo"])
    let inbox = try await store.captureInboxScreenshots(createdSince: Self.created)
    #expect(inbox.map(\.id) == ["shot"])
    #expect(inbox.first?.pixelWidth == 1170)
    #expect(try await store.keepInCaptureInbox(id: "shot"))
    #expect(try await store.captureInboxScreenshots(createdSince: Self.created).isEmpty)
    #expect(try await store.images(ids: ["photo"]).first?.asset.isScreenshot == false)
  }

  /// 이전 빌드처럼 보관 속성이 없는 스키마로 스크린샷 한 장과 사진 한 장을 쓰고 컨테이너를 놓는다.
  private static func writePreCaptureInboxRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreCaptureInboxSchema.StoredImage.self,
      PreCaptureInboxSchema.StoredCategoryMembership.self,
      PreCaptureInboxSchema.StoredTrip.self,
      PreCaptureInboxSchema.StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    for (id, isScreenshot) in [("shot", true), ("photo", false)] {
      let image = PreCaptureInboxSchema.StoredImage(assetID: id)
      image.creationDate = Self.created.addingTimeInterval(60)
      image.pixelWidth = 1170
      image.pixelHeight = 2532
      image.isScreenshot = isScreenshot
      image.labelsData = try encoder.encode([ImageLabel]())
      context.insert(image)
    }
    try context.save()
  }
}
