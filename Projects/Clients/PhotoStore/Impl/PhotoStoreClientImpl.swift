import Core
import Foundation
import PhotoStoreInterface
import SwiftData

/// SwiftData 기반 구현.
public struct PhotoStoreClientImpl: PhotoStoreClient {
  /// `@ModelActor` 는 만든 스레드의 큐에서 SwiftData 작업을 실행하므로, App 이 메인에서 이 타입을 만들어도
  /// 저장·조회가 메인을 막지 않도록 actor 는 메인 밖 Task 에서 만든다.
  private let store: Task<PhotoStore, Never>

  /// - Parameter url: 저장 파일 위치. App 이 정해 넘기므로 위젯과 나눠 쓸 때(App Group) App 에서만 바꾸면 된다.
  ///   상위 폴더는 저장소 전용이어야 한다. 그 폴더를 통째로 기기 백업에서 뺀다.
  public init(url: URL) throws(PhotoStoreError) {
    var folder = url.deletingLastPathComponent()
    do {
      // 처음 실행하면 Application Support 같은 상위 폴더가 아직 없을 수 있다.
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      // 저장 결과는 보관함에서 다시 만들 수 있고 OCR 텍스트가 iCloud·컴퓨터 백업으로 나가지 않게 한다 (docs/ARCHITECTURE.md §4).
      // SQLite 가 나중에 만드는 -wal·-shm 파일도 빠지도록 파일이 아니라 폴더에 표시한다.
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try folder.setResourceValues(values)
    } catch {
      throw .failed
    }
    // 기본값(.automatic)은 앱에 CloudKit 권한이 생기면 OCR 줄까지 iCloud 로 동기화하므로, 권한과 관계없이 끈다.
    try self.init(configuration: ModelConfiguration(url: url, cloudKitDatabase: .none))
  }

  init(configuration: ModelConfiguration) throws(PhotoStoreError) {
    let container: ModelContainer
    do {
      container = try ModelContainer(
        for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
        configurations: configuration
      )
    } catch {
      throw .failed
    }
    self.store = Task.detached { PhotoStore(modelContainer: container) }
  }

  /// 테스트용 메모리 저장소.
  static func inMemory() throws(PhotoStoreError) -> PhotoStoreClientImpl {
    try PhotoStoreClientImpl(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
  }

  public func save(_ images: [IndexedImage]) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.save(images) }
  }

  public func delete(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.delete(ids: ids) }
  }

  public func indexedIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try await Self.perform { try await self.store.value.indexedIDs() }
  }

  public func pendingTextRecognitionIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try await Self.perform { try await self.store.value.pendingTextRecognitionIDs() }
  }

  public func gifticonExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try await Self.perform { try await self.store.value.gifticonExtractionPendingIDs() }
  }

  public func saveGifticons(_ gifticons: [ImageAsset.ID: GifticonInfo]) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.saveGifticons(gifticons) }
  }

  public func gifticonModelFillPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try await Self.perform { try await self.store.value.gifticonModelFillPendingIDs() }
  }

  public func saveGifticonModelFills(
    _ results: [ImageAsset.ID: GifticonModelFillResult]
  ) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.saveGifticonModelFills(results) }
  }

  public func receiptExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try await Self.perform { try await self.store.value.receiptExtractionPendingIDs() }
  }

  public func saveReceipts(_ receipts: [ImageAsset.ID: ReceiptInfo]) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.saveReceipts(receipts) }
  }

  public func receipts() async throws(PhotoStoreError) -> [ReceiptListItem] {
    try await Self.perform { try await self.store.value.receipts() }
  }

  public func captureGroupExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try await Self.perform { try await self.store.value.captureGroupExtractionPendingIDs() }
  }

  public func saveCaptureGroups(_ groups: [ImageAsset.ID: CaptureGroups]) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.saveCaptureGroups(groups) }
  }

  public func captureGroupItems(in category: ImageCategory) async throws(PhotoStoreError) -> [CaptureGroupItem] {
    try await Self.perform { try await self.store.value.captureGroupItems(in: category) }
  }

  public func searchEntries() async throws(PhotoStoreError) -> SearchEntries {
    let (rows, pendingTextCount) = try await Self.perform { try await self.store.value.searchRows() }
    return await SearchEntries(entries: Self.searchEntries(from: rows), pendingTextCount: pendingTextCount)
  }

  public func captureInboxScreenshots(createdSince: Date) async throws(PhotoStoreError) -> [ImageAsset] {
    try await Self.perform { try await self.store.value.captureInboxScreenshots(createdSince: createdSince) }
  }

  public func keepInCaptureInbox(id: ImageAsset.ID) async throws(PhotoStoreError) -> Bool {
    try await Self.perform { try await self.store.value.keepInCaptureInbox(id: id) }
  }

  public func images(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) -> [IndexedImage] {
    try await Self.perform { try await self.store.value.images(ids: ids) }
  }

  public func images(in category: ImageCategory) async throws(PhotoStoreError) -> [IndexedImage] {
    try await Self.perform { try await self.store.value.images(in: category) }
  }

  public func assets(in category: ImageCategory) async throws(PhotoStoreError) -> [ImageAsset] {
    try await Self.perform { try await self.store.value.assets(in: category) }
  }

  public func upcomingGifticonExpiries(from date: LocalDate) async throws(PhotoStoreError) -> [GifticonExpiry] {
    try await Self.perform { try await self.store.value.upcomingGifticonExpiries(from: date) }
  }

  public func gifticons() async throws(PhotoStoreError) -> [GifticonListItem] {
    try await Self.perform { try await self.store.value.gifticons() }
  }

  public func gifticon(id: ImageAsset.ID) async throws(PhotoStoreError) -> GifticonListItem? {
    try await Self.perform { try await self.store.value.gifticon(id: id) }
  }

  public func setGifticonUsed(_ isUsed: Bool, id: ImageAsset.ID) async throws(PhotoStoreError) -> Bool {
    try await Self.perform { try await self.store.value.setGifticonUsed(isUsed, id: id) }
  }

  public func categoryCounts() async throws(PhotoStoreError) -> [ImageCategory: Int] {
    try await Self.perform { try await self.store.value.categoryCounts() }
  }

  public func replaceTrips(_ trips: [Trip]) async throws(PhotoStoreError) {
    try await Self.perform { try await self.store.value.replaceTrips(trips) }
  }

  public func trips() async throws(PhotoStoreError) -> [Trip] {
    try await Self.perform { try await self.store.value.trips() }
  }

  public func tripCount() async throws(PhotoStoreError) -> Int {
    try await Self.perform { try await self.store.value.tripCount() }
  }

  public func assets(ids: [ImageAsset.ID]) async throws(PhotoStoreError) -> [ImageAsset] {
    try await Self.perform { try await self.store.value.assets(ids: ids) }
  }

  public func assets(
    in categories: Set<ImageCategory>,
    createdIn interval: DateInterval
  ) async throws(PhotoStoreError) -> [ImageCategory: [ImageAsset]] {
    try await Self.perform { try await self.store.value.assets(in: categories, createdIn: interval) }
  }

  public func places(
    for keys: Set<RoundedCoordinate>,
    localeIdentifier: String
  ) async throws(PhotoStoreError) -> [RoundedCoordinate: CachedPlace] {
    try await Self.perform { try await self.store.value.places(for: keys, localeIdentifier: localeIdentifier) }
  }

  public func savePlace(
    _ name: CachedPlaceName,
    timeZoneIdentifier: String?,
    for key: RoundedCoordinate,
    localeIdentifier: String
  ) async throws(PhotoStoreError) -> Bool {
    try await Self.perform {
      try await self.store.value.savePlace(
        name,
        timeZoneIdentifier: timeZoneIdentifier,
        for: key,
        localeIdentifier: localeIdentifier
      )
    }
  }

  /// 줄 텍스트만 디코딩한다(신뢰도·사각형을 만들지 않아 전체 디코딩의 약 1/4). 메인과 저장소 actor 밖에서 돈다.
  @concurrent
  private static func searchEntries(from rows: [PhotoStore.SearchRow]) async -> [SearchEntry] {
    let decoder = PropertyListDecoder()
    return rows.map { row in
      let lines = (try? decoder.decode([StoredLineText].self, from: row.textLinesData))?.map(\.text) ?? []
      return SearchEntry(asset: row.asset, lines: lines, captureGroups: row.captureGroups)
    }
  }

  /// `RecognizedTextLine` 의 `text` 키만 읽는다.
  private struct StoredLineText: Decodable {
    let text: String
  }

  /// SwiftData·인코딩 실패를 `.failed` 로 바꾼다. 원인 오류에는 OCR 텍스트가 섞일 수 있어 남기지 않는다.
  private static func perform<Output>(_ operation: () async throws -> Output) async throws(PhotoStoreError) -> Output {
    do {
      return try await operation()
    } catch {
      throw .failed
    }
  }
}
