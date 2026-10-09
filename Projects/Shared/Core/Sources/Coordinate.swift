/// 위도·경도. Interface 에 `CLLocationCoordinate2D` 를 노출하지 않기 위한 값 타입 (docs/ARCHITECTURE.md §4).
public struct Coordinate: Sendable, Hashable, Codable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}
