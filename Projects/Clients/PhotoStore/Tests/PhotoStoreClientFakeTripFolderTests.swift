import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 여행 폴더 시드·훅·실패·기록. 같은 동작은 `PhotoStoreTripFolderTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeTripFolderTests {
  @Test("시드 장소의 이름은 정한 locale 로 캐시된 것이고, 이름 없는 시드는 시간대만 있다")
  func seedsPlacesWithLocale() async throws {
    let fake = PhotoStoreClientFake(
      places: [
        PhotoStoreTripFolderTests.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul"),
        PhotoStoreTripFolderTests.tokyo: CachedPlace(name: nil, timeZoneIdentifier: "Asia/Tokyo"),
      ],
      placesLocaleIdentifier: "en_US"
    )
    let keys: Set = [PhotoStoreTripFolderTests.jeju, PhotoStoreTripFolderTests.tokyo]

    #expect(try await fake.places(for: keys, localeIdentifier: "en_US") == [
      PhotoStoreTripFolderTests.jeju: CachedPlace(name: .named("제주시"), timeZoneIdentifier: "Asia/Seoul"),
      PhotoStoreTripFolderTests.tokyo: CachedPlace(name: nil, timeZoneIdentifier: "Asia/Tokyo"),
    ])
    #expect(try await fake.places(for: keys, localeIdentifier: "ko_KR") == [
      PhotoStoreTripFolderTests.jeju: CachedPlace(name: nil, timeZoneIdentifier: "Asia/Seoul"),
      PhotoStoreTripFolderTests.tokyo: CachedPlace(name: nil, timeZoneIdentifier: "Asia/Tokyo"),
    ])
    #expect(fake.placesCallCount == 2)
  }

  @Test("여행 읽기는 정한 번째 호출만 실패하고, 훅은 성공한 호출에서 계산한 뒤 번호를 받는다")
  func failsTripsByCallAndCallsHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      tripsErrors: [1: .failed],
      onTrips: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.replaceTrips([PhotoStoreTripFolderTests.jejuTrip])
        }
      }
    )
    fake.set(instance)

    // 훅을 기다리는 동안 바꾼 여행은 이미 계산한 결과에 들지 않는다.
    #expect(try await instance.trips().isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await instance.trips()
    }
    #expect(try await instance.trips() == [PhotoStoreTripFolderTests.jejuTrip])
    #expect(instance.tripsCallCount == 3)
    #expect(indexes.withLock { $0 } == [0, 2])
  }

  @Test("식별자 조회는 정한 번째 호출만 실패하고, 훅은 계산한 뒤 번호를 받는다")
  func failsTripAssetsByCallAndCallsHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      tripAssetsErrors: [1: .failed],
      onTripAssets: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.save([PhotoStoreTripFolderTests.image("a", at: 0)])
        }
      }
    )
    fake.set(instance)

    #expect(try await instance.assets(ids: ["a"]).isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await instance.assets(ids: ["a"])
    }
    #expect(try await instance.assets(ids: ["a"]).map(\.id) == ["a"])
    #expect(indexes.withLock { $0 } == [0, 2])
  }

  @Test("기간 조회는 정한 번째 호출만 실패하고, 훅은 계산한 뒤 번호를 받는다")
  func failsPeriodAssetsByCallAndCallsHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      periodAssetsErrors: [1: .failed],
      onPeriodAssets: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.save([PhotoStoreTripFolderTests.image("r", at: 150, categories: [.receipt])])
        }
      }
    )
    fake.set(instance)
    let interval = PhotoStoreTripFolderTests.interval(100, 200)

    #expect(try await instance.assets(in: [.receipt], createdIn: interval).isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await instance.assets(in: [.receipt], createdIn: interval)
    }
    #expect(try await instance.assets(in: [.receipt], createdIn: interval).mapValues { $0.map(\.id) }
      == [.receipt: ["r"]])
    #expect(indexes.withLock { $0 } == [0, 2])
  }

  @Test("장소 실패는 캐시 읽기·쓰기만 던지고 캐시를 바꾸지 않으며, 다른 호출은 성공한다")
  func placeErrorFailsOnlyPlaceCalls() async throws {
    let fake = PhotoStoreClientFake(trips: [PhotoStoreTripFolderTests.jejuTrip], placeError: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.places(for: [PhotoStoreTripFolderTests.jeju], localeIdentifier: "ko_KR")
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.savePlace(
        .named("제주시"), timeZoneIdentifier: nil, for: PhotoStoreTripFolderTests.jeju, localeIdentifier: "ko_KR"
      )
    }
    #expect(try await fake.trips() == [PhotoStoreTripFolderTests.jejuTrip])
    #expect(fake.savedPlaces.isEmpty)
    #expect(fake.placesCallCount == 1)
  }

  @Test("캐시에 쓴 것만 기록하고, 여행이 없어 false 인 쓰기는 기록하지 않는다")
  func recordsOnlySavedPlaces() async throws {
    let fake = PhotoStoreClientFake(trips: [PhotoStoreTripFolderTests.jejuTrip])

    _ = try await fake.savePlace(
      .named("제주시"), timeZoneIdentifier: "Asia/Seoul", for: PhotoStoreTripFolderTests.jeju, localeIdentifier: "ko_KR"
    )
    _ = try await fake.savePlace(
      .unnamed,
      timeZoneIdentifier: nil,
      for: PhotoStoreTripFolderTests.tokyo,
      localeIdentifier: "ko_KR"
    )

    #expect(fake.savedPlaces == [
      SavedPlace(
        key: PhotoStoreTripFolderTests.jeju,
        localeIdentifier: "ko_KR",
        name: .named("제주시"),
        timeZoneIdentifier: "Asia/Seoul"
      ),
    ])
  }
}

/// 훅이 만들기 전의 대역을 참조하도록 나중에 채운다.
private final class Later<Value: Sendable>: Sendable {
  private let storage = Mutex<Value?>(nil)

  var value: Value? {
    self.storage.withLock { $0 }
  }

  func set(_ value: Value) {
    self.storage.withLock { $0 = value }
  }
}
