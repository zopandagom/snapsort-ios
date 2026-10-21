import Core
import Foundation
import Testing

struct RoundedCoordinateTests {
  @Test(
    "값×100 을 가장 가까운 정수로, 0.5 는 0 에서 먼 쪽으로 반올림한다",
    arguments: [
      (0.005, 1),
      (-0.005, -1),
      // 1.005 의 이진 값은 1.00499… 라 1.00 이 된다.
      (1.005, 100),
      (37.565, 3757),
      (-37.565, -3757),
      (37.575, 3758),
      (-0.004, 0),
      (90, 9000),
      (-90, -9000),
    ]
  )
  func roundsLatitude(latitude: Double, hundredths: Int) throws {
    let rounded = try #require(RoundedCoordinate(Coordinate(latitude: latitude, longitude: 0)))
    #expect(rounded.latitudeHundredths == hundredths)
  }

  @Test("-0.0 은 0 이고 좌표도 양의 0 이다")
  func normalizesNegativeZero() throws {
    let rounded = try #require(RoundedCoordinate(Coordinate(latitude: -0.0, longitude: -0.0)))

    #expect(rounded.latitudeHundredths == 0)
    #expect(rounded.longitudeHundredths == 0)
    #expect(rounded.coordinate.latitude.sign == .plus)
    #expect(rounded.coordinate.longitude.sign == .plus)
  }

  @Test("경도 180 은 -180 과 같은 자오선이라 -18000 으로 둔다", arguments: [179.995, 180, -180])
  func normalizesAntimeridian(longitude: Double) throws {
    let rounded = try #require(RoundedCoordinate(Coordinate(latitude: 0, longitude: longitude)))
    #expect(rounded.longitudeHundredths == -18000)
  }

  @Test(
    "유한하지 않거나 범위 밖 좌표는 만들지 않는다",
    arguments: [
      Coordinate(latitude: .nan, longitude: 0),
      Coordinate(latitude: 0, longitude: .nan),
      Coordinate(latitude: .infinity, longitude: 0),
      Coordinate(latitude: 0, longitude: -.infinity),
      Coordinate(latitude: 91, longitude: 0),
      Coordinate(latitude: -90.001, longitude: 0),
      Coordinate(latitude: 0, longitude: -181),
      Coordinate(latitude: 0, longitude: 180.001),
    ]
  )
  func rejectsInvalidCoordinates(coordinate: Coordinate) {
    #expect(RoundedCoordinate(coordinate) == nil)
  }

  @Test("정수로 만들 때 범위 밖이면 nil, 경도 18000 은 -18000 이다")
  func makesFromHundredths() throws {
    #expect(RoundedCoordinate(latitudeHundredths: 9001, longitudeHundredths: 0) == nil)
    #expect(RoundedCoordinate(latitudeHundredths: -9001, longitudeHundredths: 0) == nil)
    #expect(RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: 18001) == nil)
    #expect(RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: -18001) == nil)

    let antimeridian = try #require(RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: 18000))
    #expect(antimeridian.longitudeHundredths == -18000)
    #expect(antimeridian == RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: -18000))
    let jeju = try #require(RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    #expect(jeju.coordinate == Coordinate(latitude: 33.5, longitude: 126.53))
  }

  @Test("정수/100 좌표를 다시 반올림하면 모든 위도·경도에서 같은 정수다")
  func roundTripsAllHundredths() throws {
    var latitudeFailures: [Int] = []
    for latitude in -9000 ... 9000 {
      let key = try #require(RoundedCoordinate(latitudeHundredths: latitude, longitudeHundredths: 0))
      if RoundedCoordinate(key.coordinate)?.latitudeHundredths != latitude {
        latitudeFailures.append(latitude)
      }
    }
    var longitudeFailures: [Int] = []
    for longitude in -18000 ... 17999 {
      let key = try #require(RoundedCoordinate(latitudeHundredths: 0, longitudeHundredths: longitude))
      if RoundedCoordinate(key.coordinate)?.longitudeHundredths != longitude {
        longitudeFailures.append(longitude)
      }
    }

    #expect(latitudeFailures.isEmpty)
    #expect(longitudeFailures.isEmpty)
  }

  @Test("여행 키는 중심점의 반올림이고 중심점이 유효하지 않으면 nil 이다")
  func tripPlaceKey() {
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let jeju = Trip(
      assetIDs: ["a"],
      startDate: start,
      endDate: start,
      center: Coordinate(latitude: 33.4996, longitude: 126.5312)
    )
    let invalid = Trip(
      assetIDs: ["a"],
      startDate: start,
      endDate: start,
      center: Coordinate(latitude: .nan, longitude: 0)
    )

    #expect(jeju.placeKey == RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653))
    #expect(invalid.placeKey == nil)
  }
}
