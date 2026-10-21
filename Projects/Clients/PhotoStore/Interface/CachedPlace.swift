/// 캐시된 장소 이름. 캐시에 없음은 `CachedPlace.name` 이 nil 인 것으로 나타낸다.
public enum CachedPlaceName: Sendable, Equatable {
  case named(String)
  /// 장소 항목은 왔는데 쓸 이름 필드가 없었다. 다시 묻지 않는다.
  case unnamed
}

/// 여행 중심점(반올림) 하나의 장소 캐시 (docs/ARCHITECTURE.md §4 저장소).
public struct CachedPlace: Sendable, Equatable {
  /// 요청한 locale 로 캐시된 이름. locale 이 다르면 nil(다시 묻는다).
  public let name: CachedPlaceName?
  /// 여행지 시간대 식별자. locale 과 무관하다.
  public let timeZoneIdentifier: String?

  public init(name: CachedPlaceName?, timeZoneIdentifier: String?) {
    self.name = name
    self.timeZoneIdentifier = timeZoneIdentifier
  }
}
