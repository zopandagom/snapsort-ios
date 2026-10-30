import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import TripPlaceImpl

/// 저장소 출입 막기 (앱이 뒤로 갈 때·BG 작업 끝): 진행 중 저장소 호출이 끝날 때까지 기다리고, 막은 뒤 온 응답은 쓰지 않고 버리며,
/// 막은 동안 회차는 저장소를 읽지 않는다.
@Suite(.timeLimit(.minutes(1)))
struct TripPlaceClientImplHoldTests {
  typealias Fixture = TripPlaceFixture

  @Test("진행 중 저장소 호출이 있으면 막기는 그 호출이 끝날 때까지 기다린다")
  func holdWaitsForInFlightStoreCall() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let entered = Gate()
    let release = Gate()
    let store = PhotoStoreClientFake(trips: [trip], onTrips: { _ in
      entered.open()
      await release.wait()
    })
    let client = try Fixture.client(map: MapClientFake(placeNameResults: Fixture.namedResults([trip])), store: store)

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await entered.wait()
    let held = Mutex(false)
    let holding = Task {
      await client.holdStoreAccess()
      held.withLock { $0 = true }
    }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!held.withLock { $0 })

    release.open()
    await holding.value
    await round.value

    #expect(store.savedPlaces.isEmpty)
  }

  @Test("막은 뒤 온 응답은 캐시에 쓰지 않고 알리지 않으며, 다시 열면 다음 회차가 그 키를 다시 묻는다")
  func dropsResponseArrivingWhileHeld() async throws {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let respond = Gate()
    let map = try MapClientFake(placeNameResults: Fixture.namedResults([trip])) { call in
      if call == 0 {
        await respond.wait()
      }
    }
    let store = PhotoStoreClientFake(trips: [trip])
    let client = Fixture.client(map: map, store: store)
    let changes = await ChangeCounter(client)

    let round = Task { await client.prefetchPlaces(locale: Fixture.locale) }
    await waitUntil { map.placeNameRequests.count == 1 }
    await client.holdStoreAccess()
    respond.open()
    await round.value

    #expect(store.savedPlaces.isEmpty)
    #expect(changes.value == 0)

    await client.allowStoreAccess()
    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(map.placeNameRequests.count == 2)
    #expect(try store.savedPlaces.map(\.key) == [Fixture.key(trip)])
    changes.cancel()
  }

  @Test("막은 동안 회차는 저장소를 읽지 않고 바로 돌아온다")
  func roundSkipsStoreWhileHeld() async {
    let trip = Fixture.trip(day: 1, latitude: 10)
    let map = MapClientFake()
    let store = PhotoStoreClientFake(trips: [trip])
    let client = Fixture.client(map: map, store: store)

    await client.holdStoreAccess()
    await client.prefetchPlaces(locale: Fixture.locale)

    #expect(store.tripsCallCount == 0)
    #expect(map.placeNameRequests.isEmpty)
  }
}
