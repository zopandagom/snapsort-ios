import Foundation

/// 여행 장소 이름 미리 받기 (docs/ARCHITECTURE.md §4 위치·지도 원칙 ①). 저장된 여행 중심점 중 지금 로캘 이름이 캐시에 없는 것을
/// 한 번에 하나씩 간격을 두고 역지오코딩해 장소 캐시에 쓴다. 다른 Client(Map·PhotoStore)를 조합한다.
/// 좌표를 받는 인자가 없다: 보내는 좌표는 구현이 저장된 여행의 반올림 중심점(`Trip.placeKey`)에서만 만든다.
/// 구현은 TripPlaceImpl, 테스트 대역은 TripPlaceTesting 에 있다.
public protocol TripPlaceClient: Sendable {
  /// 회차 하나. 저장된 여행 중심점 중 이 로캘 이름이 캐시에 없는 키를 최신 여행부터 하나씩 묻고 캐시에 쓴다.
  /// 돌아오면 회차가 끝났다(다 받음·상한·실패·시한·취소·저전력·최소 간격 안·이미 도는 중). 실패는 던지지 않는다.
  /// 부른 Task 를 취소하면 다음 요청을 내지 않고 바로 돌아온다(진행 중 요청은 끝까지 가서 캐시에 쓴다).
  func prefetchPlaces(locale: Locale) async

  /// 미리 받기가 장소 캐시에 쓸 때마다 하나(회차가 끝난 뒤 늦게 온 응답 포함). 구독을 끝내면(Task 취소) 끝난다.
  /// 받는 쪽이 늦게 읽으면 여러 번의 쓰기가 하나로 합쳐진다.
  func placeChanges() async -> AsyncStream<Void>

  /// 장소 캐시 읽기·쓰기를 막고, 진행 중 저장소 호출이 끝날 때까지 기다린다. 앱이 뒤로 가 저장소에서 손을 떼야 할 때 부른다.
  /// 막은 동안 회차는 저장소를 읽지 않고 바로 돌아오고, 늦게 온 응답은 캐시에 쓰지 않고 버린다(다음 회차가 다시 묻는다. 간격 기록은 그대로 한다).
  func holdStoreAccess() async

  /// 막은 저장소 출입을 다시 연다.
  func allowStoreAccess() async
}
