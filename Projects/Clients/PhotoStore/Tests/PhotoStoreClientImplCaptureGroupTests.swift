import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// 저장소가 쓰지 않는 캡처 묶음 값 조합(버전·식별자)을 직접 쓰는 행.
private struct StoredGroupRow {
  var version = CaptureGroupExtractor.rulesVersion
  var mallID: String?
  var brandID: String?
  var chatAppID: String?
  var regionIDs: String?
}

/// Impl 만의 캡처 묶음 동작: 규칙 버전, 해석 불가 행, 경량 이전. 같은 동작은 `PhotoStoreCaptureGroupTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplCaptureGroupTests {
  @Test("규칙 버전이 다르거나 식별자를 목록에서 풀지 못하는 행은 추출하지 않은 것으로 읽어 추출 대기에 들고 목록에서 확인 중이다")
  func unreadableRowsArePending() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let rows: [String: StoredGroupRow] = [
      "oldVersion": StoredGroupRow(version: CaptureGroupExtractor.rulesVersion + 1, mallID: "coupang"),
      "notExtracted": StoredGroupRow(version: 0),
      "unknownMall": StoredGroupRow(mallID: "noSuchMall"),
      "unknownBrand": StoredGroupRow(brandID: "noSuchBrand"),
      "unknownApp": StoredGroupRow(chatAppID: "noSuchApp"),
      "wrongProvince": StoredGroupRow(regionIDs: "busan:강남구"),
      "generalDistrict": StoredGroupRow(regionIDs: "gyeonggi:분당구"),
      "emptyString": StoredGroupRow(regionIDs: ""),
      "emptyPiece": StoredGroupRow(regionIDs: "seoul,,busan"),
      "valid": StoredGroupRow(mallID: "coupang", brandID: "nike", regionIDs: "busan:해운대구,seoul:강남구"),
    ]
    try Self.writeRows(at: url) { context, encoder in
      for (id, row) in rows {
        let stored = try Self.groupRow(id, encoder: encoder, in: context)
        stored.captureGroupRulesVersion = row.version
        stored.shoppingMallID = row.mallID
        stored.shoppingBrandID = row.brandID
        stored.chatAppID = row.chatAppID
        stored.mapRegionIDs = row.regionIDs
      }
    }
    let store = try PhotoStoreClientImpl(url: url)
    let valid = try CaptureGroups(
      mall: ShoppingMall(id: "coupang"),
      brand: ShoppingBrand(id: "nike"),
      regions: [#require(KoreanRegion(id: "busan:해운대구")), #require(KoreanRegion(id: "seoul:강남구"))]
    )
    let invalidIDs = Set(rows.keys).subtracting(["valid"])

    let read = try await Dictionary(uniqueKeysWithValues: store.images(in: .shopping).map { ($0.id, $0.captureGroups) })
    #expect(read == Dictionary(uniqueKeysWithValues: rows.keys.map { ($0, $0 == "valid" ? valid : nil) }))
    #expect(try await store.captureGroupExtractionPendingIDs() == invalidIDs)
    let statuses = try await Dictionary(uniqueKeysWithValues: store.captureGroupItems(in: .shopping).map { (
      $0.id,
      $0.status
    ) })
    #expect(statuses == Dictionary(uniqueKeysWithValues: rows.keys.map { (
      $0,
      $0 == "valid" ? .extracted(valid) : .checking
    ) }))

    let fresh = CaptureGroups(mall: ShoppingMall(id: "musinsa"))
    try await store.saveCaptureGroups(Dictionary(uniqueKeysWithValues: rows.keys.map { ($0, fresh) }))

    let rewritten = try await Dictionary(uniqueKeysWithValues: store.images(in: .shopping).map { (
      $0.id,
      $0.captureGroups
    ) })
    #expect(rewritten == Dictionary(uniqueKeysWithValues: rows.keys.map { ($0, $0 == "valid" ? valid : fresh) }))
    #expect(try await store.captureGroupExtractionPendingIDs().isEmpty)
  }

  @Test("캡처 묶음 속성 전 저장 파일이 경량 이전으로 열리고, 기존 쇼핑·대화·지도 읽음 행은 추출 대기, 기프티콘·영수증 값·여행·장소 캐시는 그대로다")
  func migratesStoreSavedBeforeCaptureGroups() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writePreCaptureGroupRows(at: url)

    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.indexedIDs() == ["shoppingRead", "mapRead", "chatOCRPending", "gifticon", "receipt"])
    #expect(try await store.captureGroupExtractionPendingIDs() == ["shoppingRead", "mapRead"])
    #expect(try await store.captureGroupItems(in: .shopping).map(\.status) == [.checking])
    #expect(try await store.captureGroupItems(in: .chat).map(\.status) == [.checking])
    let gifticon = try #require(try await store.images(ids: ["gifticon"]).first)
    #expect(gifticon.gifticon == GifticonInfo(
      expiryDate: LocalDate(year: 2026, month: 12, day: 31),
      redemptionPlace: "예시카페"
    ))
    #expect(gifticon.captureGroups == nil)
    #expect(try await store.images(ids: ["receipt"]).first?.receipt == ReceiptStoreFixture.found)
    #expect(try await store.receiptExtractionPendingIDs().isEmpty)
    #expect(try await store.trips().map(\.assetIDs) == [["p1", "p2"]])
    #expect(try await store.places(for: [PhotoStoreTripFolderTests.jeju], localeIdentifier: "ko_KR")
      == [PhotoStoreTripFolderTests.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul")])

    try await store.saveCaptureGroups(["shoppingRead": CaptureGroupStoreFixture.shopping])
    #expect(try await store.images(ids: ["shoppingRead"]).first?.captureGroups == CaptureGroupStoreFixture.shopping)
    #expect(try await store.captureGroupExtractionPendingIDs() == ["mapRead"])
  }

  @Test("지역은 정렬한 식별자로 저장해 순서와 관계없이 같은 값으로 왕복한다")
  func roundTripsRegionsInAnyOrder() async throws {
    let store = try PhotoStoreClientImpl.inMemory()
    let regions: Set<KoreanRegion> = try [
      #require(KoreanRegion(id: "jeju")), #require(KoreanRegion(id: "gyeonggi:성남시")),
      #require(KoreanRegion(id: "seoul:중구")),
      #require(KoreanRegion(id: "busan:중구")),
    ]

    try await store.save([CaptureGroupStoreFixture.image("a", .map, groups: CaptureGroups(regions: regions))])

    #expect(try await store.images(ids: ["a"]).first?.captureGroups?.regions == regions)
    #expect(try await store.captureGroupItems(in: .map).map(\.status) == [.extracted(CaptureGroups(regions: regions))])
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

  private static func groupRow(
    _ id: String,
    encoder: PropertyListEncoder,
    in context: ModelContext
  ) throws -> StoredImage {
    let stored = StoredImage(assetID: id)
    stored.labelsData = try encoder.encode([ImageLabel]())
    stored.needsTextRecognition = true
    stored.textLinesData = try encoder.encode(CaptureGroupStoreFixture.lines)
    context.insert(stored)
    // 지역은 지도 카테고리에서만 읽히므로 쇼핑이면서 지도인 행으로 둔다.
    stored.memberships = [ImageCategory.shopping, .map].map { StoredCategoryMembership(category: $0.rawValue) }
    return stored
  }

  /// 이전 빌드처럼 캡처 묶음 속성이 없는 스키마로 쇼핑·지도 읽음 행, 대화 OCR 대기 행, 기프티콘·영수증 추출 행, 제주 여행과 장소 캐시를 쓰고
  /// 컨테이너를 놓는다.
  private static func writePreCaptureGroupRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreCaptureGroupSchema.StoredImage.self,
      PreCaptureGroupSchema.StoredCategoryMembership.self,
      PreCaptureGroupSchema.StoredTrip.self,
      PreCaptureGroupSchema.StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let encoder = PropertyListEncoder()
    let rows: [String: (category: ImageCategory, isRead: Bool)] = [
      "shoppingRead": (.shopping, true),
      "mapRead": (.map, true),
      "chatOCRPending": (.chat, false),
      "gifticon": (.gifticon, true),
      "receipt": (.receipt, true),
    ]
    for (id, row) in rows {
      try Self.insertPreCaptureGroupImage(id, category: row.category, isRead: row.isRead, in: context, encoder: encoder)
    }
    Self.insertPreCaptureGroupTrip(in: context)
    try context.save()
  }

  private static func insertPreCaptureGroupImage(
    _ id: String,
    category: ImageCategory,
    isRead: Bool,
    in context: ModelContext,
    encoder: PropertyListEncoder
  ) throws {
    let image = PreCaptureGroupSchema.StoredImage(assetID: id)
    image.creationDate = Date(timeIntervalSince1970: 1_700_000_000)
    image.labelsData = try encoder.encode([ImageLabel]())
    image.needsTextRecognition = true
    image.textLinesData = isRead ? try encoder.encode(CaptureGroupStoreFixture.lines) : nil
    if category == .gifticon {
      image.gifticonRulesVersion = GifticonExtractor.rulesVersion
      image.gifticonExpiryDay = 20_261_231
      image.gifticonRedemptionPlace = "예시카페"
      image.gifticonModelVersion = GifticonExtractor.modelFillVersion
      image.gifticonExpiryFromModel = false
      image.gifticonRedemptionPlaceFromModel = false
    }
    if category == .receipt {
      image.receiptRulesVersion = ReceiptExtractor.rulesVersion
      image.receiptStoreName = "(주)예시마트"
      image.receiptAmountMinorUnits = 9000
      image.receiptCurrencyCode = "KRW"
    }
    context.insert(image)
    image.memberships = [PreCaptureGroupSchema.StoredCategoryMembership(category: category.rawValue)]
  }

  private static func insertPreCaptureGroupTrip(in context: ModelContext) {
    let trip = PhotoStoreTripFolderTests.jejuTrip
    context.insert(PreCaptureGroupSchema.StoredTrip(
      assetIDs: ["p1", "p2"],
      startDate: trip.startDate,
      endDate: trip.endDate,
      centerLatitude: trip.center.latitude,
      centerLongitude: trip.center.longitude
    ))
    context.insert(PreCaptureGroupSchema.StoredPlaceName(
      latitudeHundredths: PhotoStoreTripFolderTests.jeju.latitudeHundredths,
      longitudeHundredths: PhotoStoreTripFolderTests.jeju.longitudeHundredths,
      localeIdentifier: "ko_KR",
      name: "제주시",
      timeZoneIdentifier: "Asia/Seoul"
    ))
  }
}
