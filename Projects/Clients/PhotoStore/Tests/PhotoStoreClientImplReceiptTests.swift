import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// 저장소가 쓰지 않는 영수증 값 조합(버전·최소 단위·통화 코드)을 직접 쓰는 행.
private struct StoredReceiptRow {
  let version: Int
  let minorUnits: Int?
  let code: String?
}

/// Impl 만의 영수증 동작: 규칙 버전, 해석 불가 행, 경량 이전, 상한 금액 왕복. 같은 동작은 `PhotoStoreReceiptTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplReceiptTests {
  @Test("규칙 버전이 다르거나 통화 코드를 모르거나 금액·통화 한쪽만 있거나 음수·상한 초과인 행은 추출하지 않은 것으로 읽어 추출 대기에 들고 목록에서 확인 중이다")
  func unreadableRowsArePending() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let version = ReceiptExtractor.rulesVersion
    let rows: [String: StoredReceiptRow] = [
      "oldVersion": StoredReceiptRow(version: version + 1, minorUnits: 9000, code: "KRW"),
      "notExtracted": StoredReceiptRow(version: 0, minorUnits: nil, code: nil),
      "unknownCode": StoredReceiptRow(version: version, minorUnits: 9000, code: "GBP"),
      "amountOnly": StoredReceiptRow(version: version, minorUnits: 9000, code: nil),
      "codeOnly": StoredReceiptRow(version: version, minorUnits: nil, code: "KRW"),
      "negative": StoredReceiptRow(version: version, minorUnits: -1, code: "KRW"),
      "overLimit": StoredReceiptRow(version: version, minorUnits: ReceiptAmount.maximumMinorUnits + 1, code: "KRW"),
      "valid": StoredReceiptRow(version: version, minorUnits: 9000, code: "KRW"),
    ]
    try Self.writeRows(at: url) { context, encoder in
      for (id, row) in rows {
        let stored = try Self.receiptRow(id, encoder: encoder, in: context)
        stored.receiptRulesVersion = row.version
        stored.receiptStoreName = "예시마트"
        stored.receiptAmountMinorUnits = row.minorUnits
        stored.receiptCurrencyCode = row.code
      }
    }
    let store = try PhotoStoreClientImpl(url: url)
    let valid = ReceiptInfo(
      storeName: "예시마트",
      amount: ReceiptAmount(minorUnits: 9000, currency: .krw),
      isCancelled: false
    )
    let invalidIDs: Set<String> = Set(rows.keys).subtracting(["valid"])

    let read = try await Dictionary(uniqueKeysWithValues: store.images(in: .receipt).map { ($0.id, $0.receipt) })
    #expect(read == Dictionary(uniqueKeysWithValues: rows.keys.map { ($0, $0 == "valid" ? valid : nil) }))
    #expect(try await store.receiptExtractionPendingIDs() == invalidIDs)
    let statuses = try await Dictionary(uniqueKeysWithValues: store.receipts().map { ($0.id, $0.status) })
    #expect(statuses == Dictionary(uniqueKeysWithValues: rows.keys.map { (
      $0,
      $0 == "valid" ? .extracted(valid) : .checking
    ) }))

    let fresh = ReceiptInfo(storeName: "새 가게", amount: nil, isCancelled: true)
    try await store.saveReceipts(Dictionary(uniqueKeysWithValues: rows.keys.map { ($0, fresh) }))

    let rewritten = try await Dictionary(uniqueKeysWithValues: store.images(in: .receipt).map { ($0.id, $0.receipt) })
    #expect(rewritten == Dictionary(uniqueKeysWithValues: rows.keys.map { ($0, $0 == "valid" ? valid : fresh) }))
    #expect(try await store.receiptExtractionPendingIDs().isEmpty)
  }

  @Test("영수증 속성 전 저장 파일이 경량 이전으로 열리고, 기존 영수증 읽음 행은 추출 대기, 기프티콘 값·여행·장소 캐시는 그대로다")
  func migratesStoreSavedBeforeReceiptValues() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writePreReceiptRows(at: url)

    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.indexedIDs() == ["receiptRead", "receiptOCRPending", "gifticon"])
    #expect(try await store.receiptExtractionPendingIDs() == ["receiptRead"])
    #expect(try await store.receipts().map(\.status) == [.checking, .checking])
    let gifticon = try #require(try await store.images(ids: ["gifticon"]).first)
    #expect(gifticon.gifticon == GifticonInfo(
      expiryDate: LocalDate(year: 2026, month: 12, day: 31),
      redemptionPlace: "예시카페"
    ))
    #expect(gifticon.receipt == nil)
    #expect(try await store.trips().map(\.assetIDs) == [["p1", "p2"]])
    #expect(try await store.places(for: [PhotoStoreTripFolderTests.jeju], localeIdentifier: "ko_KR")
      == [PhotoStoreTripFolderTests.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul")])

    let found = ReceiptInfo(
      storeName: "예시마트",
      amount: ReceiptAmount(minorUnits: 9000, currency: .krw),
      isCancelled: false
    )
    try await store.saveReceipts(["receiptRead": found])
    #expect(try await store.images(ids: ["receiptRead"]).first?.receipt == found)
    #expect(try await store.receiptExtractionPendingIDs().isEmpty)
  }

  @Test("상한 금액(10^12 최소 단위)과 통화 코드를 그대로 왕복한다", arguments: ReceiptCurrency.allCases)
  func roundTripsMaximumAmount(currency: ReceiptCurrency) async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let info = ReceiptInfo(
      storeName: "(주)예시상사",
      amount: ReceiptAmount(minorUnits: ReceiptAmount.maximumMinorUnits, currency: currency),
      isCancelled: true
    )

    try await store.save([ReceiptStoreFixture.receipt("a", info: info)])

    #expect(try await store.images(ids: ["a"]).first?.receipt == info)
    #expect(try await store.receipts().map(\.status) == [.extracted(info)])
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

  private static func receiptRow(
    _ id: String,
    encoder: PropertyListEncoder,
    in context: ModelContext
  ) throws -> StoredImage {
    let stored = StoredImage(assetID: id)
    stored.labelsData = try encoder.encode([ImageLabel]())
    stored.needsTextRecognition = true
    stored.textLinesData = try encoder.encode(ReceiptStoreFixture.lines)
    context.insert(stored)
    stored.memberships = [StoredCategoryMembership(category: ImageCategory.receipt.rawValue)]
    return stored
  }

  /// 이전 빌드처럼 영수증 속성이 없는 스키마로 영수증 읽음·OCR 대기 행, 기프티콘 추출 행, 제주 여행과 장소 캐시를 쓰고 컨테이너를 놓는다.
  private static func writePreReceiptRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreReceiptSchema.StoredImage.self,
      PreReceiptSchema.StoredCategoryMembership.self,
      PreReceiptSchema.StoredTrip.self,
      PreReceiptSchema.StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    let rows: [String: (category: ImageCategory, isRead: Bool)] = [
      "receiptRead": (.receipt, true),
      "receiptOCRPending": (.receipt, false),
      "gifticon": (.gifticon, true),
    ]
    let created: [String: TimeInterval] = ["receiptRead": 1_700_000_200, "receiptOCRPending": 1_700_000_100]
    for (id, row) in rows {
      let image = PreReceiptSchema.StoredImage(assetID: id)
      image.creationDate = Date(timeIntervalSince1970: created[id] ?? 1_700_000_000)
      image.labelsData = try encoder.encode([ImageLabel]())
      image.needsTextRecognition = true
      image.textLinesData = row.isRead ? try encoder.encode(ReceiptStoreFixture.lines) : nil
      if row.category == .gifticon {
        image.gifticonRulesVersion = GifticonExtractor.rulesVersion
        image.gifticonExpiryDay = 20_261_231
        image.gifticonRedemptionPlace = "예시카페"
        image.gifticonModelVersion = GifticonExtractor.modelFillVersion
        image.gifticonExpiryFromModel = false
        image.gifticonRedemptionPlaceFromModel = false
      }
      context.insert(image)
      image.memberships = [PreReceiptSchema.StoredCategoryMembership(category: row.category.rawValue)]
    }
    let trip = PhotoStoreTripFolderTests.jejuTrip
    context.insert(PreReceiptSchema.StoredTrip(
      assetIDs: ["p1", "p2"],
      startDate: trip.startDate,
      endDate: trip.endDate,
      centerLatitude: trip.center.latitude,
      centerLongitude: trip.center.longitude
    ))
    context.insert(PreReceiptSchema.StoredPlaceName(
      latitudeHundredths: PhotoStoreTripFolderTests.jeju.latitudeHundredths,
      longitudeHundredths: PhotoStoreTripFolderTests.jeju.longitudeHundredths,
      localeIdentifier: "ko_KR",
      name: "제주시",
      timeZoneIdentifier: "Asia/Seoul"
    ))
    try context.save()
  }
}
