import Core
import Foundation

/// 지도 앱·장소 이름 (docs/ARCHITECTURE.md §4 위치·지도). 주소로 지도 앱을 열고, 여행 중심점의 장소 이름을 역지오코딩한다.
/// 구현은 MapImpl, 테스트 대역은 MapTesting 에 있다.
public protocol MapClient: Sendable {
  /// 주소 문자열을 지도 앱 검색으로 연다. 사용자가 누를 때만 부른다(주소는 사진에서 읽은 텍스트다).
  /// 앱은 주소를 지오코딩하지 않고 문자열을 그대로 지도 앱에 넘긴다. 지도 앱을 열지 못하면(지운 경우 등) false.
  /// 주소는 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
  func openInMaps(address: String) async -> Bool

  /// 반올림 중심점 근처 장소. 항목이 없으면(`placemarkNotFound`) nil, 요청 실패는 던진다.
  /// 여행 폴더 상세를 열 때 그 여행 중심점으로만 부른다. 좌표·이름은 로그에 남기지 않는다.
  /// 받은 Task 가 취소돼도 요청은 끝까지 간다(MapKit 이 취소를 받지 않는다).
  func placeName(near coordinate: RoundedCoordinate, locale: Locale) async throws(PlaceNameError) -> PlaceInfo?
}

/// 역지오코딩으로 받은 장소.
public struct PlaceInfo: Sendable, Equatable {
  /// cityWithContext → cityName → regionName 중 처음 값(예: "제주특별자치도 제주시"). 쓸 필드가 없으면 nil(이름 없음, 캐시한다).
  public let name: String?
  /// 여행지 시간대 식별자(`MKMapItem.timeZone`, 예: "Asia/Seoul", 바다는 "GMT-1000"). 없으면 nil.
  public let timeZoneIdentifier: String?

  public init(name: String?, timeZoneIdentifier: String?) {
    self.name = name
    self.timeZoneIdentifier = timeZoneIdentifier
  }
}

/// 장소 이름을 받지 못한 이유. 네트워크 없음·요청 수 제한 등은 모두 failed (캐시하지 않는다).
public enum PlaceNameError: Error, Equatable {
  case failed
}
