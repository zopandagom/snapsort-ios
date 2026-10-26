import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// 저장 위치·옮기기(`preparedStoreURL`)와 위젯용 읽기 전용 열기(`sharedStoreURL`·`init(readingAt:)`).
/// 실제로는 App 이 옛 위치를 열기 전에 옮기므로, 옛 위치에 쓴 저장소 인스턴스는 옮기기 전에 놓는다.
struct PhotoStoreLocationTests {
  private static let created = Date(timeIntervalSince1970: 1_700_000_000)

  /// 임시 폴더 하나 아래에 group 컨테이너와 옛 위치의 부모(Application Support 역할)를 둔다.
  private struct Folders {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    var group: URL { self.root.appending(path: "Group", directoryHint: .isDirectory) }
    var legacyParent: URL { self.root.appending(path: "ApplicationSupport", directoryHint: .isDirectory) }
    var groupFolder: URL { self.group.appending(path: "PhotoStore", directoryHint: .isDirectory) }
    var groupStore: URL { self.groupFolder.appending(path: "PhotoStore.store") }
    var movingFolder: URL { self.group.appending(path: "PhotoStore.moving", directoryHint: .isDirectory) }
    var legacyFolder: URL { self.legacyParent.appending(path: "PhotoStore", directoryHint: .isDirectory) }
    var legacyStore: URL { self.legacyFolder.appending(path: "PhotoStore.store") }

    init() throws {
      try FileManager.default.createDirectory(at: self.group, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: self.legacyParent, withIntermediateDirectories: true)
    }

    func prepare() -> URL {
      PhotoStoreClientImpl.preparedStoreURL(groupContainer: self.group, legacyParent: self.legacyParent)
    }

    func remove() {
      try? FileManager.default.removeItem(at: self.root)
    }
  }

  // MARK: - preparedStoreURL

  @Test("새 설치면 group 위치를 돌려주고 아무것도 만들지 않는다")
  func newInstallReturnsGroupWithoutCreating() throws {
    let folders = try Folders()
    defer { folders.remove() }

    #expect(folders.prepare() == folders.groupStore)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folders.group.path(percentEncoded: false)).isEmpty)
    #expect(!Self.exists(folders.legacyFolder))
  }

  @Test("옛 위치에만 있으면 폴더째 group 으로 옮기고, 사용함·보관 표시가 그대로다")
  func movesLegacyFolderKeepingUserMarks() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeMarkedRows(at: folders.legacyStore)
    // -wal·-shm 은 놓은 저장소가 닫힐 때 없어질 수 있어, 같은 폴더의 표지 파일로 폴더째 옮겨지는지 본다.
    try Data("sentinel".utf8).write(to: folders.legacyFolder.appending(path: "sentinel"))

    let url = folders.prepare()

    #expect(url == folders.groupStore)
    #expect(!Self.exists(folders.legacyFolder))
    #expect(!Self.exists(folders.movingFolder))
    #expect(try Self.fileNames(in: folders.groupFolder).isSuperset(of: ["PhotoStore.store", "sentinel"]))
    #expect(try Self.isExcludedFromBackup(folders.groupFolder))
    try await Self.expectMarkedRows(in: PhotoStoreClientImpl(url: url))
  }

  @Test("양쪽에 다 있으면 group 을 쓰고 옛 위치와 group 내용을 건드리지 않는다")
  func keepsBothWhenBothExist() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeRows(["group"], at: folders.groupStore)
    try await Self.writeRows(["legacy"], at: folders.legacyStore)

    let url = folders.prepare()

    #expect(url == folders.groupStore)
    #expect(Self.exists(folders.legacyStore))
    #expect(try await PhotoStoreClientImpl(url: folders.groupStore).indexedIDs() == ["group"])
    #expect(try await PhotoStoreClientImpl(url: folders.legacyStore).indexedIDs() == ["legacy"])
  }

  @Test("group 폴더가 저장 파일 없이 남아 있으면 지우고 옛 위치에서 옮긴다")
  func replacesGroupFolderWithoutStore() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeRows(["legacy"], at: folders.legacyStore)
    try FileManager.default.createDirectory(at: folders.groupFolder, withIntermediateDirectories: true)
    try Data("left".utf8).write(to: folders.groupFolder.appending(path: "leftover"))

    let url = folders.prepare()

    #expect(url == folders.groupStore)
    #expect(!Self.exists(folders.groupFolder.appending(path: "leftover")))
    #expect(!Self.exists(folders.legacyFolder))
    #expect(try await PhotoStoreClientImpl(url: url).indexedIDs() == ["legacy"])
  }

  @Test("복사 중 끝나 임시 폴더가 남았으면 지우고 옛 위치에서 다시 옮기며, 사용함 표시가 그대로다")
  func retriesAfterInterruptedCopy() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeMarkedRows(at: folders.legacyStore)
    // 일부만 복사된 임시 폴더: 저장 파일 앞부분만 있다.
    try FileManager.default.createDirectory(at: folders.movingFolder, withIntermediateDirectories: true)
    let partial = try Data(contentsOf: folders.legacyStore).prefix(100)
    try partial.write(to: folders.movingFolder.appending(path: "PhotoStore.store"))

    let url = folders.prepare()

    #expect(url == folders.groupStore)
    #expect(!Self.exists(folders.movingFolder))
    #expect(!Self.exists(folders.legacyFolder))
    try await Self.expectMarkedRows(in: PhotoStoreClientImpl(url: url))
  }

  @Test("group 에 있고 임시 폴더가 남았으면 임시 폴더만 지운다")
  func removesLeftoverMovingFolderWhenGroupExists() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeRows(["group"], at: folders.groupStore)
    try FileManager.default.createDirectory(at: folders.movingFolder, withIntermediateDirectories: true)

    let url = folders.prepare()

    #expect(url == folders.groupStore)
    #expect(!Self.exists(folders.movingFolder))
    #expect(try await PhotoStoreClientImpl(url: url).indexedIDs() == ["group"])
  }

  @Test("옮기지 못하면 옛 위치를 돌려주고 옛 폴더를 그대로 두며 임시 폴더를 남기지 않는다")
  func fallsBackToLegacyWhenMoveFails() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeRows(["legacy"], at: folders.legacyStore)
    // group 컨테이너 자리에 파일이 있어 그 아래에 폴더를 만들 수 없다.
    let blocked = folders.root.appending(path: "BlockedGroup")
    try Data("file".utf8).write(to: blocked)

    let url = PhotoStoreClientImpl.preparedStoreURL(groupContainer: blocked, legacyParent: folders.legacyParent)

    #expect(url == folders.legacyStore)
    #expect(Self.exists(folders.legacyStore))
    #expect(!Self.exists(blocked.appending(path: "PhotoStore.moving")))
    #expect(try await PhotoStoreClientImpl(url: url).indexedIDs() == ["legacy"])
  }

  @Test("group 컨테이너가 없으면(서명 없는 빌드) 옛 위치를 돌려준다")
  func returnsLegacyWithoutGroupContainer() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try await Self.writeRows(["legacy"], at: folders.legacyStore)

    let url = PhotoStoreClientImpl.preparedStoreURL(groupContainer: nil, legacyParent: folders.legacyParent)

    #expect(url == folders.legacyStore)
    #expect(Self.exists(folders.legacyStore))
  }

  // MARK: - 위젯 읽기

  @Test("위젯이 읽을 위치는 group 컨테이너가 없거나 저장 파일이 없으면 nil 이다")
  func sharedStoreURLRequiresStoreFile() async throws {
    let folders = try Folders()
    defer { folders.remove() }

    #expect(PhotoStoreClientImpl.sharedStoreURL(groupContainer: nil) == nil)
    #expect(PhotoStoreClientImpl.sharedStoreURL(groupContainer: folders.group) == nil)
    try await Self.writeRows(["group"], at: folders.groupStore)
    #expect(PhotoStoreClientImpl.sharedStoreURL(groupContainer: folders.group) == folders.groupStore)
  }

  @Test("읽기 전용으로 열면 앱이 쓴 행이 보이고, 쓰기는 실패하며 값이 바뀌지 않는다")
  func readOnlyStoreReadsButCannotWrite() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    let writer = try PhotoStoreClientImpl(url: folders.groupStore)
    try await writer.save([Self.gifticon("coffee", expiryDate: Self.date(2026, 12, 31))])

    let reader = try PhotoStoreClientImpl(readingAt: folders.groupStore)

    #expect(try await reader.upcomingGifticonExpiries(from: Self.date(2026, 1, 1)).map(\.imageID) == ["coffee"])
    #expect(try await reader.gifticonExtractionPendingIDs().isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await reader.setGifticonUsed(true, id: "coffee")
    }
    #expect(try await writer.upcomingGifticonExpiries(from: Self.date(2026, 1, 1)).map(\.imageID) == ["coffee"])
  }

  @Test("읽기 전용 저장소는 앱이 나중에 쓴 값도 다시 읽는다")
  func readOnlyStoreSeesLaterWrites() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    let writer = try PhotoStoreClientImpl(url: folders.groupStore)
    try await writer.save([
      Self.gifticon("coffee", expiryDate: Self.date(2026, 12, 31)),
      Self.gifticon("cake", expiryDate: Self.date(2026, 12, 30)),
    ])
    let reader = try PhotoStoreClientImpl(readingAt: folders.groupStore)
    #expect(try await reader.upcomingGifticonExpiries(from: Self.date(2026, 1, 1)).count == 2)

    #expect(try await writer.setGifticonUsed(true, id: "cake"))

    #expect(try await reader.upcomingGifticonExpiries(from: Self.date(2026, 1, 1)).map(\.imageID) == ["coffee"])
  }

  @Test("없는 파일을 읽기 전용으로 열면 실패하고 파일을 만들지 않는다")
  func readOnlyStoreFailsForMissingFile() throws {
    let folders = try Folders()
    defer { folders.remove() }

    #expect(throws: PhotoStoreError.failed) {
      try PhotoStoreClientImpl(readingAt: folders.groupStore)
    }
    #expect(!Self.exists(folders.groupStore))
  }

  @Test("이전 전 스키마 파일은 읽기 전용으로 열지 못하고 파일이 그대로라, 앱이 열면 이전된다")
  func readOnlyStoreDoesNotMigrate() async throws {
    let folders = try Folders()
    defer { folders.remove() }
    try Self.writePreSimilarPhotoRow(at: folders.groupStore)
    let before = try Data(contentsOf: folders.groupStore)

    #expect(throws: PhotoStoreError.failed) {
      try PhotoStoreClientImpl(readingAt: folders.groupStore)
    }

    #expect(try Data(contentsOf: folders.groupStore) == before)
    #expect(try await PhotoStoreClientImpl(url: folders.groupStore).indexedIDs() == ["old"])
  }

  // MARK: - 픽스처

  /// 사용함 표시한 기프티콘·미사용 기프티콘, 보관한 스크린샷·보관하지 않은 스크린샷을 쓰고 저장소를 놓는다.
  private static func writeMarkedRows(at url: URL) async throws {
    let store = try PhotoStoreClientImpl(url: url)
    try await store.save([
      Self.gifticon("used", expiryDate: Self.date(2026, 12, 31)),
      Self.gifticon("unused", expiryDate: Self.date(2026, 12, 31)),
      .stub(id: "kept", creationDate: Self.created, isScreenshot: true),
      .stub(id: "shot", creationDate: Self.created, isScreenshot: true),
    ])
    #expect(try await store.setGifticonUsed(true, id: "used"))
    #expect(try await store.keepInCaptureInbox(id: "kept"))
  }

  private static func expectMarkedRows(in store: PhotoStoreClientImpl) async throws {
    #expect(try await store.upcomingGifticonExpiries(from: self.date(2026, 1, 1)).map(\.imageID) == ["unused"])
    #expect(try await store.captureInboxScreenshots(createdSince: self.created).map(\.id) == ["shot"])
  }

  private static func writeRows(_ ids: [String], at url: URL) async throws {
    let store = try PhotoStoreClientImpl(url: url)
    try await store.save(ids.map { IndexedImage.stub(id: $0) })
  }

  /// 이전 빌드처럼 특징 벡터 속성이 없는 스키마로 한 행을 쓰고 컨테이너를 놓는다.
  private static func writePreSimilarPhotoRow(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreSimilarPhotoSchema.StoredImage.self,
      PreSimilarPhotoSchema.StoredCategoryMembership.self,
      PreSimilarPhotoSchema.StoredTrip.self,
      PreSimilarPhotoSchema.StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let image = PreSimilarPhotoSchema.StoredImage(assetID: "old")
    image.labelsData = try PropertyListEncoder().encode([ImageLabel]())
    context.insert(image)
    try context.save()
  }

  private static func gifticon(_ id: String, expiryDate: LocalDate) -> IndexedImage {
    .stub(
      id: id,
      textRecognition: .recognized(GifticonListFixture.lines),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: nil)
    )
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
    try #require(LocalDate(year: year, month: month, day: day))
  }

  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }

  private static func fileNames(in folder: URL) throws -> Set<String> {
    try Set(FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))
  }

  private static func isExcludedFromBackup(_ folder: URL) throws -> Bool {
    try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
  }
}
