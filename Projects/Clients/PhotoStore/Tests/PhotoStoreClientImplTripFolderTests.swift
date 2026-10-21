import Core
import Foundation
import PhotoStoreInterface
import SwiftData
import Testing
@testable import PhotoStoreImpl

/// Impl 만의 여행 폴더 동작: 경량 이전, 같은 키 행 정리. 같은 동작은 `PhotoStoreTripFolderTests` 가 Fake 와 함께 본다.
struct PhotoStoreClientImplTripFolderTests {
  @Test("장소 캐시 전 저장 파일이 열리고, 이미지·여행은 그대로이며 캐시는 비었다가 이어서 쓸 수 있다")
  func migratesStoreSavedBeforeTripFolder() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writePreTripFolderRows(at: url)

    let store = try PhotoStoreClientImpl(url: url)

    #expect(try await store.indexedIDs() == ["a"])
    #expect(try await store.assets(in: .receipt).map(\.id) == ["a"])
    let trip = try #require(try await store.trips().first)
    #expect(trip.assetIDs == ["p1", "p2"])
    #expect(trip.placeKey == PhotoStoreTripFolderTests.jeju)
    #expect(try await store.places(for: [PhotoStoreTripFolderTests.jeju], localeIdentifier: "ko_KR").isEmpty)
    #expect(try await store.savePlace(
      .named("제주시"),
      timeZoneIdentifier: "Asia/Seoul",
      for: PhotoStoreTripFolderTests.jeju,
      localeIdentifier: "ko_KR"
    ))
    #expect(try await store.places(for: [PhotoStoreTripFolderTests.jeju], localeIdentifier: "ko_KR")
      == [PhotoStoreTripFolderTests.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul")])
  }

  @Test("같은 키 행이 여럿 남아 있으면 쓸 때 하나로 줄인다")
  func savingCollapsesDuplicateRows() async throws {
    let url = GifticonListFixture.temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Self.writeDuplicatePlaceRows(at: url)
    let store = try PhotoStoreClientImpl(url: url)
    try await store.replaceTrips([PhotoStoreTripFolderTests.jejuTrip])

    #expect(try await store.savePlace(
      .unnamed,
      timeZoneIdentifier: "Asia/Seoul",
      for: PhotoStoreTripFolderTests.jeju,
      localeIdentifier: "ko_KR"
    ))

    #expect(try await store.places(for: [PhotoStoreTripFolderTests.jeju], localeIdentifier: "ko_KR")
      == [PhotoStoreTripFolderTests.jeju: CachedPlace(name: .unnamed, timeZoneIdentifier: "Asia/Seoul")])
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredPlaceName>()) == 1)
  }

  /// 이전 빌드처럼 장소 캐시 엔티티가 없는 스키마로 영수증 이미지 하나와 제주 여행 하나를 쓰고 컨테이너를 놓는다.
  private static func writePreTripFolderRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: PreTripFolderSchema.StoredImage.self,
      PreTripFolderSchema.StoredCategoryMembership.self,
      PreTripFolderSchema.StoredTrip.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let image = PreTripFolderSchema.StoredImage(assetID: "a")
    image.labelsData = try PropertyListEncoder().encode([ImageLabel]())
    context.insert(image)
    image.memberships = [PreTripFolderSchema.StoredCategoryMembership(category: ImageCategory.receipt.rawValue)]
    let trip = PhotoStoreTripFolderTests.jejuTrip
    context.insert(
      PreTripFolderSchema.StoredTrip(
        assetIDs: ["p1", "p2"],
        startDate: trip.startDate,
        endDate: trip.endDate,
        centerLatitude: trip.center.latitude,
        centerLongitude: trip.center.longitude
      )
    )
    try context.save()
  }

  /// 같은 제주 키의 캐시 행 둘을 지금 스키마로 직접 쓰고 컨테이너를 놓는다.
  private static func writeDuplicatePlaceRows(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let container = try ModelContainer(
      for: StoredImage.self, StoredCategoryMembership.self, StoredTrip.self, StoredPlaceName.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    for name in ["제주시", "제주"] {
      context.insert(
        StoredPlaceName(
          latitudeHundredths: 3350,
          longitudeHundredths: 12653,
          localeIdentifier: "ko_KR",
          name: name,
          timeZoneIdentifier: nil
        )
      )
    }
    try context.save()
  }
}
