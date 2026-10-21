/// 소수점 2자리(약 1km)로 반올림한 위도·경도. 장소 이름 캐시 키이자 지오코딩에 보내는 유일한 좌표 (docs/ARCHITECTURE.md §4 위치·지도).
/// 값×100 정수로 들고 있어 부동소수 비교·-0.0 문제가 없다.
public struct RoundedCoordinate: Sendable, Hashable {
  /// -9000...9000
  public let latitudeHundredths: Int
  /// -18000...17999. 경도 180 은 -180 과 같은 자오선이라 -18000 으로 둔다.
  public let longitudeHundredths: Int

  /// 값×100 을 가장 가까운 정수로(0.5 는 0 에서 먼 쪽). Double 의 이진 값으로 계산하므로 1.005(실제 1.00499…)는 1.00 이다.
  /// 유한하지 않거나 위도 -90…90·경도 -180…180 밖이면 nil (반올림 전 값으로 판단).
  public init?(_ coordinate: Coordinate) {
    let latitude = coordinate.latitude
    let longitude = coordinate.longitude
    guard latitude.isFinite, longitude.isFinite, (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude)
    else {
      return nil
    }
    self.init(
      latitudeHundredths: Int((latitude * 100).rounded(.toNearestOrAwayFromZero)),
      longitudeHundredths: Int((longitude * 100).rounded(.toNearestOrAwayFromZero))
    )
  }

  /// 저장된 정수에서 다시 만든다. 범위 밖이면 nil, 경도 18000 은 -18000.
  public init?(latitudeHundredths: Int, longitudeHundredths: Int) {
    guard (-9000 ... 9000).contains(latitudeHundredths), (-18000 ... 18000).contains(longitudeHundredths) else {
      return nil
    }
    self.latitudeHundredths = latitudeHundredths
    self.longitudeHundredths = longitudeHundredths == 18000 ? -18000 : longitudeHundredths
  }

  /// 정수/100 좌표.
  public var coordinate: Coordinate {
    Coordinate(latitude: Double(self.latitudeHundredths) / 100, longitude: Double(self.longitudeHundredths) / 100)
  }
}

public extension Trip {
  /// 중심점의 반올림 키. 중심점이 유효하지 않으면 nil (그 여행은 지오코딩하지 않는다).
  var placeKey: RoundedCoordinate? {
    RoundedCoordinate(self.center)
  }
}
