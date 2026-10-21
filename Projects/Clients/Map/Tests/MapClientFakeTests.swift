import Core
import Foundation
import MapInterface
import MapTesting
import Synchronization
import Testing

struct MapClientFakeTests {
  @Test("받은 주소를 차례로 기록하고 정한 결과를 돌려준다")
  func recordsAddresses() async {
    let fake = MapClientFake()
    let failing = MapClientFake(openResult: false)

    #expect(await fake.openInMaps(address: "세종대로 110"))
    #expect(await fake.openInMaps(address: "테헤란로 1"))
    #expect(await failing.openInMaps(address: "세종대로 110") == false)

    #expect(fake.openedAddresses == ["세종대로 110", "테헤란로 1"])
    #expect(failing.openedAddresses == ["세종대로 110"])
  }

  @Test("훅이 기다리는 동안 이미 주소를 기록했고, 훅이 끝나면 정한 결과를 돌려준다")
  func recordsBeforeHook() async {
    let entered = Mutex(false)
    let (release, continuation) = AsyncStream.makeStream(of: Void.self)
    let fake = MapClientFake(openResult: false) {
      entered.withLock { $0 = true }
      for await _ in release {}
    }

    let open = Task { await fake.openInMaps(address: "세종대로 110") }
    while !entered.withLock({ $0 }) {
      await Task.yield()
    }
    #expect(fake.openedAddresses == ["세종대로 110"])

    continuation.finish()
    #expect(await open.value == false)
  }

  @Test("장소 이름 요청을 좌표·locale 로 기록하고 키별 결과를, 없는 키는 nil 을 돌려준다")
  func recordsPlaceNameRequests() async throws {
    let jeju = try #require(RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    let tokyo = try #require(RoundedCoordinate(latitudeHundredths: 3568, longitudeHundredths: 13976))
    let ocean = try #require(RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: -15000))
    let place = PlaceInfo(name: "제주특별자치도 제주시", timeZoneIdentifier: "Asia/Seoul")
    let fake = MapClientFake(placeNameResults: [jeju: .success(place), tokyo: .failure(.failed)])

    #expect(try await fake.placeName(near: jeju, locale: Locale(identifier: "ko_KR")) == place)
    await #expect(throws: PlaceNameError.failed) {
      try await fake.placeName(near: tokyo, locale: Locale(identifier: "en_US"))
    }
    #expect(try await fake.placeName(near: ocean, locale: Locale(identifier: "ko_KR")) == nil)

    #expect(fake.placeNameRequests == [
      PlaceNameRequest(coordinate: jeju, localeIdentifier: "ko_KR"),
      PlaceNameRequest(coordinate: tokyo, localeIdentifier: "en_US"),
      PlaceNameRequest(coordinate: ocean, localeIdentifier: "ko_KR"),
    ])
  }

  @Test("장소 이름 훅이 기다리는 동안 이미 요청을 기록했고, 인자는 호출 번호다")
  func recordsPlaceNameBeforeHook() async throws {
    let jeju = try #require(RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    let indexes = Mutex<[Int]>([])
    let (release, continuation) = AsyncStream.makeStream(of: Void.self)
    let fake = MapClientFake(onPlaceName: { index in
      indexes.withLock { $0.append(index) }
      if index == 0 {
        for await _ in release {}
      }
    })

    let first = Task { try await fake.placeName(near: jeju, locale: Locale(identifier: "ko_KR")) }
    while indexes.withLock({ $0 }).isEmpty {
      await Task.yield()
    }
    #expect(fake.placeNameRequests.count == 1)
    #expect(try await fake.placeName(near: jeju, locale: Locale(identifier: "ko_KR")) == nil)

    continuation.finish()
    #expect(try await first.value == nil)
    #expect(indexes.withLock { $0 } == [0, 1])
  }
}
