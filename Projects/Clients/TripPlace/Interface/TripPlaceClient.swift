import Foundation

/// 여행 장소 이름 미리 받기 (docs/ARCHITECTURE.md §4 위치·지도 원칙 ①). 저장된 여행 중심점 중 지금 로캘 이름이 캐시에 없는 것을
/// 한 번에 하나씩 간격을 두고 역지오코딩해 장소 캐시에 쓴다. 다른 Client(Map·PhotoStore)를 조합한다.
/// 좌표를 받는 인자가 없다: 보내는 좌표는 구현이 저장된 여행의 반올림 중심점(`Trip.placeKey`)에서만 만든다.
/// 구현은 TripPlaceImpl, 테스트 대역은 TripPlaceTesting 에 있다.
public protocol TripPlaceClient: Sendable {
  /// 회차 하나. 저장된 여행 중심점 중 이 로캘 이름이 캐시에 없는 키를 최신 여행부터 하나씩 묻고 캐시에 쓴다.
  /// 돌아오면 회차가 끝났다(다 받음·상한·실패·시한·취소·저전력·최소 간격 안·이미 도는 중). 실패는 던지지 않는다.
  /// 부른 Task 를 취소하면 다음 요청을 내지 않고 바로 돌아온다(진행 중 요청은 끝까지 가서 캐시에 쓴다).
  /// `progress` 는 물을 키를 정한 뒤 (0, n) 을 한 번(n == 0 포함), 키 하나를 처리할 때마다(물어서 끝남·그사이 캐시에 생겨 건너뜀) (i, n) 을 받는다.
  /// 회차가 시작하지 못하고 돌아오면(이미 도는 중·막음·저전력·쉼·남은 요청·저장소 읽기 실패·취소) 한 번도 받지 않는다.
  /// 도중에 멈추면(실패·시한·취소) 마지막 알림 뒤 돌아온다(끝 알림 없음). 회차를 도는 쪽이 부르므로 받는 쪽은 바로 돌아와야 한다.
  func prefetchPlaces(locale: Locale, progress: @escaping @Sendable (TripPlacePrefetchProgress) -> Void) async

  /// 미리 받기가 장소 캐시에 쓸 때마다 하나(회차가 끝난 뒤 늦게 온 응답 포함). 구독을 끝내면(Task 취소) 끝난다.
  /// 받는 쪽이 늦게 읽으면 여러 번의 쓰기가 하나로 합쳐진다.
  func placeChanges() async -> AsyncStream<Void>

  /// 장소 캐시 읽기·쓰기를 막고, 진행 중 저장소 호출이 끝날 때까지 기다린다. 앱이 뒤로 가 저장소에서 손을 떼야 할 때 부른다.
  /// 막은 동안 회차는 저장소를 읽지 않고 바로 돌아오고, 늦게 온 응답은 캐시에 쓰지 않고 버린다(다음 회차가 다시 묻는다. 간격 기록은 그대로 한다).
  func holdStoreAccess() async

  /// 막은 저장소 출입을 다시 연다.
  func allowStoreAccess() async
}

public extension TripPlaceClient {
  /// 진행을 받지 않는 회차(보관함 화면).
  func prefetchPlaces(locale: Locale) async {
    await self.prefetchPlaces(locale: locale, progress: { _ in })
  }
}

/// 미리 받기 회차 하나의 진행. 개수만 담는다(좌표·장소 이름 없음).
public struct TripPlacePrefetchProgress: Sendable, Equatable {
  /// 이번 회차에서 처리한 키 수(물어서 끝남·캐시에 이미 생겨 건너뜀 모두).
  public let doneCount: Int
  /// 이번 회차에 물을 키 수(상한 적용 뒤). 0 이면 물을 것이 없다.
  public let totalCount: Int

  public init(doneCount: Int, totalCount: Int) {
    self.doneCount = doneCount
    self.totalCount = totalCount
  }
}
