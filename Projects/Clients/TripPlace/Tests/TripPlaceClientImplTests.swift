import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import TripPlaceImpl

/// 미리 받기 회차: 순서·대상 고르기·간격·보내는 값. 실패·시한·취소는 TripPlaceClientImplFailureTests.
struct TripPlaceClientImplTests {
  typealias Fixture = TripPlaceFixture

  @Test("최신 여행부터 하나씩 묻고 캐시에 쓴다. 요청 사이에 간격을 두고 첫 요청은 기다리지 않는다")
  func requestsNewestFirstWithInterval() async throws {
    let trips = [
      Fixture.trip(day: 1, latitude: 10),
      Fixture.trip(day: 2, latitude: 20),
      Fixture.trip(day: 3, latitude: 30),
    ]
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips))
    let store = PhotoStoreClientFake(trips: trips)
    let timing = TestTiming()
    let client = Fixture.client(map: map, store: store, timing: timing)

    await client.prefetchPlaces(locale: Fixture.locale)

    let newestFirst = try trips.reversed().map(Fixture.key)
    #expect(map.placeNameRequests.map(\.coordinate) == newestFirst)
    #expect(store.savedPlaces.map(\.key) == newestFirst)
    #expect(store.savedPlaces.map(\.name) == trips.reversed().map { .named(Fixture.name($0)) })
    #expect(store.savedPlaces.allSatisfy { $0.timeZoneIdentifier == "Asia/Tokyo" && $0.localeIdentifier == "ko_KR" })
    #expect(timing.sleeps(.interval) == [.seconds(3), .seconds(3)])
  }

  @Test("보내는 값은 여행 중심점의 반올림 키와 넘긴 로캘뿐이다")
  func sendsRoundedCenterAndLocale() async throws {
    let trip = Trip(
      assetIDs: ["a"],
      startDate: Date(timeIntervalSince1970: 0),
      endDate: Date(timeIntervalSince1970: 60),
      center: Coordinate(latitude: 33.4996, longitude: 126.5312)
    )
    let map = MapClientFake()
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: [trip]))

    await client.prefetchPlaces(locale: Locale(identifier: "en_US"))

    let expected = try #require(RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    #expect(map.placeNameRequests == [PlaceNameRequest(coordinate: expected, localeIdentifier: "en_US")])
  }

  @Test("요청은 한 번에 하나만 나간다")
  func oneRequestAtATime() async throws {
    let trips = (1 ... 4).map { Fixture.trip(day: $0, latitude: Double($0 * 10)) }
    let probe = ConcurrencyProbe()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips)) { _ in
      probe.enter()
      try? await Task.sleep(for: .milliseconds(5))
      probe.leave()
    }
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips))

    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(map.placeNameRequests.count == 4)
    #expect(probe.maximum == 1)
  }

  @Test("이 로캘 이름(이름 있음·이름 없음)이 캐시된 키는 건너뛰고, 시간대만 캐시된 키는 묻는다")
  func skipsCachedNames() async throws {
    let named = Fixture.trip(day: 1, latitude: 10)
    let unnamed = Fixture.trip(day: 2, latitude: 20)
    let timeZoneOnly = Fixture.trip(day: 3, latitude: 30)
    let store = try PhotoStoreClientFake(
      trips: [named, unnamed, timeZoneOnly],
      places: [
        Fixture.key(named): CachedPlace(name: .named("서울"), timeZoneIdentifier: "Asia/Seoul"),
        Fixture.key(unnamed): CachedPlace(name: .unnamed, timeZoneIdentifier: nil),
        Fixture.key(timeZoneOnly): CachedPlace(name: nil, timeZoneIdentifier: "Asia/Tokyo"),
      ]
    )
    let map = MapClientFake()
    let client = Fixture.client(map: map, store: store)

    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(timeZoneOnly)])
  }

  @Test("다른 로캘로 캐시된 이름은 지금 로캘로 다시 받아 덮는다")
  func refetchesOtherLocale() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let store = try PhotoStoreClientFake(
      trips: [trip],
      places: [Fixture.key(trip): CachedPlace(name: .named("Seoul"), timeZoneIdentifier: "Asia/Seoul")],
      placesLocaleIdentifier: "en_US"
    )
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([trip]))
    let client = Fixture.client(map: map, store: store)

    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(map.placeNameRequests.map(\.localeIdentifier) == ["ko_KR"])
    #expect(store.savedPlaces.map(\.localeIdentifier) == ["ko_KR"])
    #expect(store.savedPlaces.map(\.name) == [.named(Fixture.name(trip))])
  }

  @Test("중심점 키가 같은 여행이 여럿이면 한 번만 묻는다")
  func dedupesSameKey() async throws {
    let trips = [Fixture.trip(day: 1, latitude: 10), Fixture.trip(day: 5, latitude: 10)]
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips))
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips))

    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(map.placeNameRequests.count == 1)
  }

  @Test("회차 하나에서 상한(30)까지만 묻는다")
  func stopsAtRoundLimit() async throws {
    let trips = (0 ..< 35).map { Fixture.trip(day: $0, latitude: Double($0)) }
    let map = MapClientFake()
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips))

    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(try map.placeNameRequests.map(\.coordinate) == trips.reversed().prefix(30).map(Fixture.key))
  }

  @Test("항목 없음은 캐시하지 않고, 같은 로캘로는 이번 실행 동안 다시 묻지 않으며 다른 로캘로는 묻는다")
  func notFoundIsRememberedPerLocale() async {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = MapClientFake()
    let store = PhotoStoreClientFake(trips: [trip])
    let client = Fixture.client(map: map, store: store)

    await client.prefetchPlaces(locale: Fixture.locale)
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)
    #expect(store.savedPlaces.isEmpty)

    await client.prefetchPlaces(locale: Locale(identifier: "en_US"))
    #expect(map.placeNameRequests.map(\.localeIdentifier) == ["ko_KR", "en_US"])
  }

  @Test("간격을 기다리는 사이 다음 키가 캐시되면(상세가 받음) 그 키는 묻지 않는다")
  func rechecksCacheBeforeRequest() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let timing = TestTiming(interval: .wait(gate))
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer]))
    let store = PhotoStoreClientFake(trips: [older, newer])
    let client = Fixture.client(map: map, store: store, timing: timing)

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { timing.sleeps(.interval).count == 1 }
    _ = try await store.savePlace(
      .named("상세"),
      timeZoneIdentifier: nil,
      for: Fixture.key(older),
      localeIdentifier: "ko_KR"
    )
    gate.open()
    await round.value

    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(newer)])
  }

  @Test("저전력 모드면 저장소를 읽지 않고 묻지 않는다")
  func skipsInLowPowerMode() async {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = MapClientFake()
    let store = PhotoStoreClientFake(trips: [trip])
    let client = Fixture.client(map: map, store: store, isLowPowerMode: true)

    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(store.tripsCallCount == 0)
    #expect(map.placeNameRequests.isEmpty)
  }

  @Test("회차가 도는 동안 부른 회차는 바로 돌아오고 요청을 늘리지 않는다")
  func reentrantRoundReturns() async throws {
    let trips = [Fixture.trip(day: 1, latitude: 10), Fixture.trip(day: 2, latitude: 20)]
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips)) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips))

    let first = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { map.placeNameRequests.count == 1 }
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)

    gate.open()
    await first.value
    #expect(map.placeNameRequests.count == 2)
  }

  @Test("캐시에 쓸 때마다 구독자 모두에게 신호가 하나 간다")
  func signalsEverySubscriberOnSave() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([trip]))
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: [trip]))
    let first = await ChangeCounter(client)
    let second = await ChangeCounter(client)
    defer {
      first.cancel()
      second.cancel()
    }

    await client.prefetchPlaces(locale: Fixture.locale)

    await waitUntil { first.value == 1 && second.value == 1 }
  }
}
