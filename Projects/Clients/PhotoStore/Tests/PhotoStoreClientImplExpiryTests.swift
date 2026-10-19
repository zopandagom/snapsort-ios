import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

struct PhotoStoreClientImplExpiryTests {
  private static let lines = [
    RecognizedTextLine(
      text: "유효기간 2026.12.31",
      confidence: 0.9,
      boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)
    ),
  ]

  @Test("만료일이 기준일과 같거나 늦은 기프티콘을 만료일 오름차순(같으면 식별자 순)으로 돌려준다")
  func listsUpcomingExpiriesInOrder() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      Self.gifticon("late", expiryDate: Self.date(2027, 1, 5)),
      Self.gifticon("b", expiryDate: Self.date(2026, 12, 31)),
      Self.gifticon("a", expiryDate: Self.date(2026, 12, 31)),
      Self.gifticon("today", expiryDate: Self.date(2026, 10, 19)),
      Self.gifticon("yesterday", expiryDate: Self.date(2026, 10, 18)),
    ])

    let expiries = try await store.upcomingGifticonExpiries(from: Self.date(2026, 10, 19))

    #expect(try expiries == [
      GifticonExpiry(imageID: "today", expiryDate: Self.date(2026, 10, 19)),
      GifticonExpiry(imageID: "a", expiryDate: Self.date(2026, 12, 31)),
      GifticonExpiry(imageID: "b", expiryDate: Self.date(2026, 12, 31)),
      GifticonExpiry(imageID: "late", expiryDate: Self.date(2027, 1, 5)),
    ])
  }

  @Test("만료일을 못 찾았거나 추출하지 않은 기프티콘은 빠진다")
  func excludesMissingExpiries() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    try await store.save([
      Self.gifticon("found", expiryDate: Self.date(2026, 12, 31)),
      Self.image("notFound", gifticon: GifticonInfo(expiryDate: nil, redemptionPlace: "스타벅스")),
      Self.image("notExtracted", gifticon: nil),
    ])

    let expiries = try await store.upcomingGifticonExpiries(from: Self.date(2026, 1, 1))

    #expect(expiries.map(\.imageID) == ["found"])
  }

  @Test("규칙 버전이 다르거나 만료일을 해석하지 못하는 행은 빠진다")
  func excludesStaleOrUnreadableRows() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      .appending(path: "PhotoStore.store")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // 저장소가 쓰지 않는 값을 직접 넣기 위해 Impl 스키마로 파일을 만들고 컨테이너를 놓은 뒤 저장소로 다시 연다.
    do {
      let container = try ModelContainer(
        for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
      )
      let context = ModelContext(container)
      let encoder = PropertyListEncoder()
      let rows: [String: (version: Int, day: Int)] = [
        "oldVersion": (GifticonExtractor.rulesVersion + 1, 20_261_231),
        "badDay": (GifticonExtractor.rulesVersion, 20_260_230),
        "valid": (GifticonExtractor.rulesVersion, 20_261_231),
      ]
      for (id, row) in rows {
        let stored = StoredImage(assetID: id)
        stored.labelsData = try encoder.encode([ImageLabel]())
        stored.needsTextRecognition = true
        stored.textLinesData = try encoder.encode(Self.lines)
        stored.gifticonRulesVersion = row.version
        stored.gifticonExpiryDay = row.day
        context.insert(stored)
        stored.memberships = [StoredCategoryMembership(category: ImageCategory.gifticon.rawValue)]
      }
      try context.save()
    }
    let store = try PhotoStoreClientImpl(url: url)

    let expiries = try await store.upcomingGifticonExpiries(from: Self.date(2026, 1, 1))

    #expect(try expiries == [GifticonExpiry(imageID: "valid", expiryDate: Self.date(2026, 12, 31))])
  }

  private static func gifticon(_ id: String, expiryDate: LocalDate) -> IndexedImage {
    self.image(id, gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: nil))
  }

  private static func image(_ id: String, gifticon: GifticonInfo?) -> IndexedImage {
    .stub(
      id: id,
      textRecognition: .recognized(self.lines),
      categories: [.gifticon],
      gifticon: gifticon
    )
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
    try #require(LocalDate(year: year, month: month, day: day))
  }
}
