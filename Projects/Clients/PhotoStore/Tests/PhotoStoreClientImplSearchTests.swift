import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// Impl 만의 검색 목록 동작: 손상된 줄 행, 옛 행, 규칙 버전이 다른 묶음 값. 같은 동작은 `PhotoStoreSearchTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplSearchTests {
  @Test("줄을 디코딩하지 못한 행은 던지지 않고 줄 없이 담고, 나머지 행은 그대로 읽는다")
  func undecodableRowKeepsListWorking() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writeRows(at: url) { context, encoder in
      let broken = StoredImage(assetID: "broken")
      broken.labelsData = try encoder.encode([ImageLabel]())
      broken.needsTextRecognition = true
      broken.textLinesData = Data("x".utf8)
      broken.creationDate = Date(timeIntervalSince1970: 200)
      context.insert(broken)

      let good = StoredImage(assetID: "good")
      good.labelsData = try encoder.encode([ImageLabel]())
      good.needsTextRecognition = true
      good.textLinesData = try encoder.encode(CaptureGroupStoreFixture.lines)
      good.creationDate = Date(timeIntervalSince1970: 100)
      context.insert(good)
    }
    let store = try PhotoStoreClientImpl(url: url)

    let result = try await store.searchEntries()

    #expect(result.entries.map(\.id) == ["broken", "good"])
    #expect(result.entries.first?.lines == [])
    #expect(result.entries.last?.lines == ["예시 화면"])
    #expect(result.pendingTextCount == 0)
  }

  @Test("옛 행(needsTextRecognition 이 false 인데 줄이 있음)도 글자를 읽은 행으로 담고 대기에는 세지 않는다")
  func legacyRowIsIncluded() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writeRows(at: url) { context, encoder in
      let legacy = StoredImage(assetID: "legacy")
      legacy.labelsData = try encoder.encode([ImageLabel]())
      legacy.needsTextRecognition = false
      legacy.textLinesData = try encoder.encode(CaptureGroupStoreFixture.lines)
      context.insert(legacy)
    }
    let store = try PhotoStoreClientImpl(url: url)

    let result = try await store.searchEntries()

    #expect(result.entries.map(\.id) == ["legacy"])
    #expect(result.entries.first?.lines == ["예시 화면"])
    #expect(result.pendingTextCount == 0)
  }

  @Test("규칙 버전이 다르거나 식별자를 풀지 못하는 묶음 값은 nil 이고 줄은 담는다")
  func staleGroupsAreNilButLinesStay() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writeRows(at: url) { context, encoder in
      let currentVersion = CaptureGroupExtractor.rulesVersion
      let rows = [
        ("oldVersion", currentVersion + 1, "coupang"),
        ("unknownMall", currentVersion, "noSuchMall"),
        ("valid", currentVersion, "coupang"),
      ]
      for (id, version, mallID) in rows {
        let stored = StoredImage(assetID: id)
        stored.labelsData = try encoder.encode([ImageLabel]())
        stored.needsTextRecognition = true
        stored.textLinesData = try encoder.encode(CaptureGroupStoreFixture.lines)
        stored.captureGroupRulesVersion = version
        stored.shoppingMallID = mallID
        context.insert(stored)
        stored.memberships = [StoredCategoryMembership(category: ImageCategory.shopping.rawValue)]
      }
    }
    let store = try PhotoStoreClientImpl(url: url)

    let byID = try await Dictionary(uniqueKeysWithValues: store.searchEntries().entries.map { ($0.id, $0) })

    #expect(byID["oldVersion"]?.captureGroups == nil)
    #expect(byID["unknownMall"]?.captureGroups == nil)
    #expect(byID["valid"]?.captureGroups == CaptureGroups(mall: ShoppingMall(id: "coupang")))
    #expect(byID.values.allSatisfy { $0.lines == ["예시 화면"] })
  }

  /// 저장소가 쓰지 않는 값을 직접 넣기 위해 Impl 스키마로 파일을 만들고 컨테이너를 놓는다.
  private static func writeRows(
    at url: URL,
    _ write: (ModelContext, PropertyListEncoder) throws -> Void
  ) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    try write(context, PropertyListEncoder())
    try context.save()
  }
}
