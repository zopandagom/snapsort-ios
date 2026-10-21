import Core
import Foundation
import MapInterface
import MapKit
import Synchronization
import Testing
@testable import MapImpl

/// 역지오코딩 응답을 장소로 바꾸는 순수 로직. 실제 MapKit 요청은 하지 않는다. 응답 값은 실측(설계 실험)에서 옮겼다.
struct MapClientImplPlaceNameTests {
  @Test("반올림 키의 정수에서 만든 좌표와 받은 locale 을 그대로 넘긴다")
  func sendsRoundedCoordinateAndLocale() async throws {
    let received = Mutex<[(Coordinate, String)]>([])
    let client = MapClientImpl { coordinate, locale throws(PlaceNameError) in
      received.withLock { $0.append((coordinate, locale.identifier)) }
      return []
    }
    let key = try #require(RoundedCoordinate(Coordinate(latitude: 33.4996, longitude: 126.5312)))

    _ = try await client.placeName(near: key, locale: Locale(identifier: "en_US"))

    let requests = received.withLock { $0 }
    #expect(requests.count == 1)
    #expect(requests.first?.0 == Coordinate(latitude: 33.5, longitude: 126.53))
    #expect(requests.first?.1 == "en_US")
  }

  @Test("항목이 없으면 nil, 있으면 이름과 첫 항목의 시간대다")
  func mapsAddressesToPlaceInfo() async throws {
    let key = try #require(RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    let empty = MapClientImpl { _, _ throws(PlaceNameError) in [] }
    let found = MapClientImpl { _, _ throws(PlaceNameError) in
      [
        PlaceAddress(cityWithContext: "", cityName: nil, regionName: nil, timeZoneIdentifier: "Asia/Seoul"),
        PlaceAddress(
          cityWithContext: "제주특별자치도 제주시",
          cityName: "제주시",
          regionName: "대한민국",
          timeZoneIdentifier: "Asia/Tokyo"
        ),
      ]
    }
    let unnamed = MapClientImpl { _, _ throws(PlaceNameError) in
      [PlaceAddress(cityWithContext: "", cityName: " ", regionName: nil, timeZoneIdentifier: "GMT-1000")]
    }

    #expect(try await empty.placeName(near: key, locale: Locale(identifier: "ko_KR")) == nil)
    #expect(try await found.placeName(near: key, locale: Locale(identifier: "ko_KR"))
      == PlaceInfo(name: "제주특별자치도 제주시", timeZoneIdentifier: "Asia/Seoul"))
    #expect(try await unnamed.placeName(near: key, locale: Locale(identifier: "ko_KR"))
      == PlaceInfo(name: nil, timeZoneIdentifier: "GMT-1000"))
  }

  @Test(
    "이름은 항목 순서대로 cityWithContext → cityName → regionName 중 공백을 지워 비지 않은 처음 값이다",
    arguments: [
      // 제주: 맥락 있는 도시 이름.
      ([PlaceAddress(cityWithContext: "제주특별자치도 제주시", cityName: "제주시", regionName: "대한민국")], "제주특별자치도 제주시"),
      // 남극: 맥락 없이 도시 이름만.
      ([PlaceAddress(cityWithContext: "", cityName: "남극대륙", regionName: nil)], "남극대륙"),
      // 바다: 도시 이름이 빈 문자열이고 맥락만.
      ([PlaceAddress(cityWithContext: "북태평양", cityName: "", regionName: nil)], "북태평양"),
      ([PlaceAddress(cityWithContext: nil, cityName: nil, regionName: "대한민국")], "대한민국"),
      ([PlaceAddress(cityWithContext: "  파리, 프랑스\n", cityName: nil, regionName: nil)], "파리, 프랑스"),
      (
        [
          PlaceAddress(cityWithContext: " ", cityName: "", regionName: nil),
          PlaceAddress(cityWithContext: nil, cityName: "일본 도쿄 지요다구", regionName: nil),
        ],
        "일본 도쿄 지요다구"
      ),
    ]
  )
  func picksPlaceName(addresses: [PlaceAddress], name: String) {
    #expect(MapClientImpl.placeName(from: addresses) == name)
  }

  @Test("쓸 이름 필드가 없거나 항목이 없으면 이름이 없다")
  func noPlaceName() {
    #expect(MapClientImpl.placeName(from: []) == nil)
    #expect(MapClientImpl.placeName(from: [PlaceAddress(cityWithContext: "", cityName: " ", regionName: "\n")]) == nil)
  }

  @Test("요청이 실패하면 그대로 failed 를 던진다")
  func rethrowsFailure() async throws {
    let key = try #require(RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    let client = MapClientImpl { _, _ throws(PlaceNameError) in throw .failed }

    await #expect(throws: PlaceNameError.failed) {
      try await client.placeName(near: key, locale: Locale(identifier: "ko_KR"))
    }
  }

  @Test("placemarkNotFound 만 항목 없음으로 본다")
  func detectsNotFound() {
    #expect(ReverseGeocoder.isNotFound(MKError(.placemarkNotFound)))
    #expect(ReverseGeocoder.isNotFound(NSError(domain: MKErrorDomain, code: 4)))
    #expect(!ReverseGeocoder.isNotFound(MKError(.serverFailure)))
    #expect(!ReverseGeocoder.isNotFound(MKError(.loadingThrottled)))
    #expect(!ReverseGeocoder.isNotFound(NSError(domain: NSURLErrorDomain, code: 4)))
    #expect(!ReverseGeocoder.isNotFound(CancellationError()))
  }
}
