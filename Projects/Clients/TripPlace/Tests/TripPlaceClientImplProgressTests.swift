import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
import TripPlaceInterface
@testable import TripPlaceImpl

/// 미리 받기 회차의 키 단위 진행 알림(계속 처리 작업의 시스템 진행 화면에 더한다).
struct TripPlaceClientImplProgressTests {
  typealias Fixture = TripPlaceFixture

  @Test("물을 키를 정한 뒤 (0, n) 을, 키를 하나 처리할 때마다 (i, n) 을 순서대로 알린다")
  func reportsEveryKey() async throws {
    let trips = (1 ... 3).map { Fixture.trip(day: $0, latitude: Double($0 * 10)) }
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips))
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips))
    let recorder = ProgressRecorder()

    await client.prefetchPlaces(locale: Fixture.locale, progress: recorder.record)

    #expect(recorder.values == [.init(0, 3), .init(1, 3), .init(2, 3), .init(3, 3)])
  }

  @Test("물을 키가 없으면 (0, 0) 을 한 번 알린다")
  func reportsZeroWhenNothingToAsk() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let store = try PhotoStoreClientFake(
      trips: [trip],
      places: [Fixture.key(trip): CachedPlace(name: .named("서울"), timeZoneIdentifier: nil)]
    )
    let recorder = ProgressRecorder()

    await Fixture.client(map: MapClientFake(), store: store).prefetchPlaces(
      locale: Fixture.locale,
      progress: recorder.record
    )

    #expect(recorder.values == [.init(0, 0)])
  }

  @Test("간격을 기다리는 사이 캐시에 생겨 건너뛴 키도 처리한 수에 든다")
  func skippedKeyCounts() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)
    let gate = Gate()
    let timing = TestTiming(interval: .wait(gate))
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer]))
    let store = PhotoStoreClientFake(trips: [older, newer])
    let client = Fixture.client(map: map, store: store, timing: timing)
    let recorder = ProgressRecorder()

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale, progress: recorder.record) }
    await waitUntil { timing.sleeps(.interval).count == 1 }
    _ = try await store.savePlace(
      .named("상세"),
      timeZoneIdentifier: nil,
      for: Fixture.key(older),
      localeIdentifier: "ko_KR"
    )
    gate.open()
    await round.value

    #expect(map.placeNameRequests.count == 1)
    #expect(recorder.values == [.init(0, 2), .init(1, 2), .init(2, 2)])
  }

  @Test("회차가 시작하지 못하면(저전력·막음·쉼) 알리지 않는다")
  func silentWhenRoundDoesNotStart() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)

    let lowPower = ProgressRecorder()
    await Fixture.client(map: MapClientFake(), store: PhotoStoreClientFake(trips: [trip]), isLowPowerMode: true)
      .prefetchPlaces(locale: Fixture.locale, progress: lowPower.record)
    #expect(lowPower.values.isEmpty)

    let held = ProgressRecorder()
    let heldClient = Fixture.client(map: MapClientFake(), store: PhotoStoreClientFake(trips: [trip]))
    await heldClient.holdStoreAccess()
    await heldClient.prefetchPlaces(locale: Fixture.locale, progress: held.record)
    #expect(held.values.isEmpty)

    let cooling = ProgressRecorder()
    let failing = try MapClientFake(placeNameResults: [Fixture.key(trip): .failure(.failed)])
    let coolingClient = Fixture.client(map: failing, store: PhotoStoreClientFake(trips: [trip]))
    await coolingClient.prefetchPlaces(locale: Fixture.locale)
    await coolingClient.prefetchPlaces(locale: Fixture.locale, progress: cooling.record)
    #expect(cooling.values.isEmpty)
  }

  @Test("회차가 도는 동안 부른 회차는 알리지 않는다")
  func silentWhenAlreadyRunning() async throws {
    let trips = [Fixture.trip(day: 1, latitude: 10), Fixture.trip(day: 2, latitude: 20)]
    let gate = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips)) { index in
      if index == 0 {
        await gate.wait()
      }
    }
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips))
    let second = ProgressRecorder()

    let first = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { map.placeNameRequests.count == 1 }
    await client.prefetchPlaces(locale: Fixture.locale, progress: second.record)
    gate.open()
    await first.value

    #expect(second.values.isEmpty)
  }

  @Test("실패나 시한으로 멈추면 멈춘 키 앞에서 끝나고 끝 알림이 없다")
  func stopsBeforeFailedKey() async throws {
    let older = Fixture.trip(day: 1, latitude: 10)
    let newer = Fixture.trip(day: 2, latitude: 20)

    let failed = ProgressRecorder()
    let failing = try MapClientFake(placeNameResults: [Fixture.key(newer): .failure(.failed)])
    await Fixture.client(map: failing, store: PhotoStoreClientFake(trips: [older, newer]))
      .prefetchPlaces(locale: Fixture.locale, progress: failed.record)
    #expect(failed.values == [.init(0, 2)])

    let timedOut = ProgressRecorder()
    let gate = Gate()
    let slow = try MapClientFake(placeNameResults: Fixture.namedResults([older, newer])) { _ in
      await gate.wait()
    }
    await Fixture.client(
      map: slow,
      store: PhotoStoreClientFake(trips: [older, newer]),
      timing: TestTiming(timeout: .immediate)
    ).prefetchPlaces(locale: Fixture.locale, progress: timedOut.record)
    gate.open()
    #expect(timedOut.values == [.init(0, 2)])
  }

  @Test("간격을 기다리는 중 취소되면 그 뒤로 알리지 않는다")
  func cancelStopsReporting() async throws {
    let trips = [Fixture.trip(day: 1, latitude: 10), Fixture.trip(day: 2, latitude: 20)]
    let map = try MapClientFake(placeNameResults: Fixture.namedResults(trips))
    let timing = TestTiming(interval: .hang)
    let client = Fixture.client(map: map, store: PhotoStoreClientFake(trips: trips), timing: timing)
    let recorder = ProgressRecorder()

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale, progress: recorder.record) }
    await waitUntil { timing.sleeps(.interval).count == 1 }
    round.cancel()
    await round.value

    #expect(recorder.values == [.init(0, 2), .init(1, 2)])
  }
}

/// 진행 알림을 받은 순서대로 모은다. 회차 actor 안에서 불리므로 Mutex 로 보호한다.
private final class ProgressRecorder: Sendable {
  private let state = Mutex<[TripPlacePrefetchProgress]>([])

  var values: [TripPlacePrefetchProgress] {
    self.state.withLock { $0 }
  }

  var record: @Sendable (TripPlacePrefetchProgress) -> Void {
    { value in self.state.withLock { $0.append(value) } }
  }
}

private extension TripPlacePrefetchProgress {
  init(_ done: Int, _ total: Int) {
    self.init(doneCount: done, totalCount: total)
  }
}
