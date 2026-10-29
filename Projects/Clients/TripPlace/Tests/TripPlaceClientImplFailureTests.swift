import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import TripPlaceImpl

/// 미리 받기 회차의 실패·시한·취소와 남은 요청.
struct TripPlaceClientImplFailureTests {
  typealias Fixture = TripPlaceFixture

  @Test("요청이 실패하면 회차를 멈추고, 최소 간격(10분)이 지나기 전 회차는 묻지 않는다")
  func failureStopsRoundUntilCooldown() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let map = try MapClientFake(placeNameResults: [Fixture.key(newer): .failure(.failed)])
    let timing = TestTiming()
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: [older, newer]), timing: timing)

    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)

    await client.prefetchPlaces(locale: Fixture.locale)
    timing.advance(by: .seconds(599))
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)

    timing.advance(by: .seconds(1))
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(newer), Fixture.key(newer)])
  }

  @Test("시한을 넘기면 회차를 멈추고, 그 요청이 돌아오지 않은 동안은 최소 간격이 지나도 새 요청을 내지 않는다")
  func timeoutBlocksNewRequestsWhileOutstanding() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer])) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let store = PhotoStoreClientFake(trips: [older, newer])
    let timing = TestTiming(timeout: .immediate)
    let client = Fixture.client(map: map, store: store, timing: timing)
    let changes = await ChangeCounter(client)
    defer { changes.cancel() }

    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)
    #expect(timing.sleeps(.timeout) == [.seconds(15)])

    timing.advance(by: .seconds(600))
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)

    // 늦은 응답도 캐시에 쓰고 알린다. 그 뒤 회차는 남은 키를 묻는다.
    timing.setTimeout(.hang)
    gate.open()
    await waitUntil { store.savedPlaces.count == 1 && changes.value == 1 }
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(newer), Fixture.key(older)])
  }

  @Test("시한을 넘긴 요청이 늦게라도 응답을 받으면 최소 간격을 기다리지 않고 다음 회차가 묻는다")
  func lateResponseLiftsTimeoutCooldown() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer])) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let store = PhotoStoreClientFake(trips: [older, newer])
    let timing = TestTiming(timeout: .immediate)
    let client = Fixture.client(map: map, store: store, timing: timing)

    await client.prefetchPlaces(locale: Fixture.locale)
    timing.setTimeout(.hang)
    gate.open()
    await waitUntil { store.savedPlaces.count == 1 }
    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(newer), Fixture.key(older)])
  }

  @Test("시한을 넘긴 요청이 늦게 실패하면 최소 간격이 그대로 남는다")
  func lateFailureKeepsCooldown() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: [Fixture.key(newer): .failure(.failed)]) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let timing = TestTiming(timeout: .immediate)
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: [older, newer]), timing: timing)

    await client.prefetchPlaces(locale: Fixture.locale)
    timing.setTimeout(.hang)
    gate.open()
    // 늦은 실패는 회차가 기다리지 않아 밖에서 보이는 것이 없으므로, 요청이 끝나 비워졌는지로 기다린다.
    let deadline = ContinuousClock.now + .seconds(30)
    while await client.hasOutstandingRequest, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await client.hasOutstandingRequest == false)
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)

    timing.advance(by: .seconds(600))
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 2)
  }

  @Test("간격을 기다리는 중 회차가 취소되면 다음 요청을 내지 않는다")
  func cancelDuringIntervalStops() async throws {
    let trips = [Fixture.trip(day: 1, latitude: 10), Fixture.trip(day: 2, latitude: 20)]
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips))
    let timing = TestTiming(interval: .hang)
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips), timing: timing)

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { timing.sleeps(.interval).count == 1 }
    round.cancel()
    await round.value

    #expect(map.placeNameRequests.count == 1)
  }

  @Test("응답을 기다리는 중 회차가 취소되면 바로 돌아오고, 요청은 끝까지 가서 캐시에 쓰고 알린다")
  func cancelDuringResponseLetsRequestFinish() async throws {
    let trips = [Fixture.trip(day: 1, latitude: 10), Fixture.trip(day: 2, latitude: 20)]
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips)) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let store = PhotoStoreClientFake(trips: trips)
    let client = Fixture.client(map: map, store: store)
    let changes = await ChangeCounter(client)
    defer { changes.cancel() }

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { map.placeNameRequests.count == 1 }
    round.cancel()
    await round.value
    #expect(store.savedPlaces.isEmpty)

    gate.open()
    await waitUntil { store.savedPlaces.count == 1 && changes.value == 1 }
    #expect(map.placeNameRequests.count == 1)
  }

  @Test("남은 요청이 시한 안이면 새 회차는 그 응답을 기다린 뒤 이어 묻는다")
  func nextRoundAwaitsOutstandingRequest() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let probe = ConcurrencyProbe()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer])) { index in
      probe.enter()
      if index == 0 {
        await gate.wait()
      }
      probe.leave()
    }
    let store = PhotoStoreClientFake(trips: [older, newer])
    let client = Fixture.client(map: map, store: store)

    let cancelled = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { map.placeNameRequests.count == 1 }
    cancelled.cancel()
    await cancelled.value

    let next = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(map.placeNameRequests.count == 1)
    gate.open()
    await next.value

    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(newer), Fixture.key(older)])
    #expect(store.savedPlaces.count == 2)
    #expect(probe.maximum == 1)
  }

  @Test("응답 사이 여행이 사라지면 쓰지 않고 알리지 않으며, 쉬지 않고 다음 키로 간다")
  func tripGoneSkipsSaveAndContinues() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer])) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let store = PhotoStoreClientFake(trips: [older, newer])
    let client = Fixture.client(map: map, store: store)
    let changes = await ChangeCounter(client)
    defer { changes.cancel() }

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { map.placeNameRequests.count == 1 }
    try await store.replaceTrips([older])
    gate.open()
    await round.value

    #expect(try map.placeNameRequests.map(\.coordinate) == [Fixture.key(newer), Fixture.key(older)])
    #expect(try store.savedPlaces.map(\.key) == [Fixture.key(older)])
    await waitUntil { changes.value == 1 }
  }

  @Test("저장소를 읽지 못하면 묻지 않고, 쉬지 않아 바로 다음 회차는 묻는다")
  func storeReadFailureDoesNotCooldown() async {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = MapClientFake()
    let store = PhotoStoreClientFake(trips: [trip], tripsErrors: [0: .failed])
    let client = Fixture.client(map: map, store: store)

    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.isEmpty)

    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)
  }

  @Test("시한 판정 전에 요청이 이미 성공해 끝났으면 쉼을 걸지 않고 회차를 이어 간다")
  func timeoutAfterFinishedSuccessContinues() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([trip]))
    let timing = TestTiming()
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: [trip]), timing: timing)
    // 시한 타이머가 먼저 이겼지만 회차가 판단하기 전에 요청 Task 가 성공으로 끝난 순서(`finishRequest` 가 먼저 돎).
    let request = try TripPlaceRequest(key: Fixture.key(trip), localeIdentifier: Fixture.locale.identifier)
    let token = await client.issueToken()
    await client.finishRequest(request, token: token, outcome: .saved)

    #expect(await client.shouldContinue(after: .timedOut, token: token))
    // 쉼이 없으니 바로 다음 회차가 묻는다.
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)
  }

  @Test("시한 판정 전에 요청이 이미 실패해 끝났으면 그 실패의 쉼으로 멈춘다")
  func timeoutAfterFinishedFailureStops() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([trip]))
    let timing = TestTiming()
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: [trip]), timing: timing)
    let request = try TripPlaceRequest(key: Fixture.key(trip), localeIdentifier: Fixture.locale.identifier)
    let token = await client.issueToken()
    await client.finishRequest(request, token: token, outcome: .failed)

    #expect(await client.shouldContinue(after: .timedOut, token: token) == false)
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.isEmpty)
    timing.advance(by: .seconds(600))
    await client.prefetchPlaces(locale: Fixture.locale)
    #expect(map.placeNameRequests.count == 1)
  }
}
