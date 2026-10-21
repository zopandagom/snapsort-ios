import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// Impl·Fake 를 같은 테스트로 본다.
enum StoreKind: CaseIterable, CustomTestStringConvertible {
  case impl
  case fake

  var testDescription: String {
    switch self {
    case .impl: "Impl"
    case .fake: "Fake"
    }
  }

  /// `images`·`trips` 를 넣고 `usedIDs` 를 사용함으로 둔 저장소. Impl 은 `save` 가 쓰지 않는 보강 상태(`.stale`·`.sourcesUnknown`)의
  /// 행을 저장 스키마로 직접 쓴 파일에서 연다.
  func make(_ images: [IndexedImage], usedIDs: Set<ImageAsset.ID> = [], trips: [Trip] = []) async throws -> TestStore {
    switch self {
    case .fake:
      return TestStore(client: PhotoStoreClientFake(images: images, trips: trips, usedIDs: usedIDs), url: nil)
    case .impl:
      let url = GifticonListFixture.temporaryStoreURL()
      let isRaw: (IndexedImage) -> Bool = { [.stale, .sourcesUnknown].contains($0.gifticonModelFill) }
      try GifticonListFixture.writeRawRows(at: url, images.filter(isRaw))
      let store = try PhotoStoreClientImpl(url: url)
      try await store.save(images.filter { !isRaw($0) })
      for id in usedIDs {
        _ = try await store.setGifticonUsed(true, id: id)
      }
      if !trips.isEmpty {
        try await store.replaceTrips(trips)
      }
      return TestStore(client: store, url: url)
    }
  }
}

struct TestStore {
  let client: any PhotoStoreClient
  let url: URL?

  /// 파일 저장소를 지운다.
  func remove() {
    if let url {
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
  }
}

/// 기프티콘 목록 테스트의 저장소·이미지 준비. 교환처와 OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
enum GifticonListFixture {
  static let lines = [
    RecognizedTextLine(
      text: "유효기간 2026.12.31",
      confidence: 0.9,
      boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)
    ),
  ]
  static let partial = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
  static let complete = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "스타벅스")

  /// 기프티콘 읽음 행. `created` 는 1970 부터 센 초.
  static func gifticon(
    _ id: String,
    info: GifticonInfo? = Self.complete,
    fill: GifticonModelFill = .done,
    created: TimeInterval? = 1_700_000_000
  ) -> IndexedImage {
    .stub(
      id: id,
      creationDate: created.map { Date(timeIntervalSince1970: $0) },
      textRecognition: .recognized(self.lines),
      categories: [.gifticon],
      gifticon: info,
      gifticonModelFill: fill
    )
  }

  static func receipt(_ id: String) -> IndexedImage {
    .stub(id: id, textRecognition: .recognized(self.lines), categories: [.receipt])
  }

  static func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
    try #require(LocalDate(year: year, month: month, day: day))
  }

  static func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "PhotoStore.store")
  }

  /// 기프티콘 읽음 행을 Impl 스키마로 직접 쓰고 컨테이너를 놓는다. `.stale` 은 다음 보강 버전, `.sourcesUnknown` 은 지금 보강 버전에
  /// 출처 속성 nil(출처 속성이 생기기 전에 마친 행)로 쓴다.
  static func writeRawRows(at url: URL, _ images: [IndexedImage]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    for image in images {
      let stored = StoredImage(assetID: image.id)
      stored.creationDate = image.asset.creationDate
      stored.labelsData = try encoder.encode(image.labels)
      stored.needsTextRecognition = true
      stored.textLinesData = try encoder.encode(image.textLines ?? [])
      PhotoStore.setGifticon(image.gifticon, on: stored)
      if image.gifticonModelFill == .sourcesUnknown {
        stored.gifticonModelVersion = GifticonExtractor.modelFillVersion
        stored.gifticonExpiryFromModel = nil
        stored.gifticonRedemptionPlaceFromModel = nil
      } else {
        stored.gifticonModelVersion = GifticonExtractor.modelFillVersion + 1
      }
      context.insert(stored)
      stored.memberships = image.categories.map { StoredCategoryMembership(category: $0.rawValue) }
    }
    try context.save()
  }
}
