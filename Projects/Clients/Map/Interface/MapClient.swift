/// 지도 앱 (docs/ARCHITECTURE.md §4 위치·지도). 지금은 주소로 지도 앱 열기만 한다. 역지오코딩은 여행 폴더 작업에서 더한다.
/// 구현은 MapImpl, 테스트 대역은 MapTesting 에 있다.
public protocol MapClient: Sendable {
  /// 주소 문자열을 지도 앱 검색으로 연다. 사용자가 누를 때만 부른다(주소는 사진에서 읽은 텍스트다).
  /// 앱은 주소를 지오코딩하지 않고 문자열을 그대로 지도 앱에 넘긴다. 지도 앱을 열지 못하면(지운 경우 등) false.
  /// 주소는 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
  func openInMaps(address: String) async -> Bool
}
