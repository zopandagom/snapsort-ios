/// 로컬 알림. 서버 푸시 없음 (docs/ARCHITECTURE.md §4 만료 알림).
/// 구현은 NotificationImpl, 테스트 대역은 NotificationTesting 에 있다.
public protocol NotificationClient: Sendable {
  /// 팝업 없이 지금 권한 상태를 읽는다.
  func authorizationStatus() async -> NotificationAuthorization

  /// 권한 팝업을 띄우고(이미 정했으면 팝업 없이) 그 뒤 상태를 돌려준다. 요청이 실패하면 지금 상태를 돌려준다.
  func requestAuthorization() async -> NotificationAuthorization

  /// 이 앱이 예약해 아직 울리지 않은 알림의 식별자.
  func pendingRequestIDs() async -> Set<String>

  /// 차례로 예약한다. 실패한 요청은 건너뛰고 끝까지 넣은 뒤, 하나라도 실패했으면 `.failed` 를 던진다(실패한 것만 빠진다).
  func add(_ requests: [NotificationRequest]) async throws(NotificationError)

  /// 대기 알림을 지운다. 없는 식별자는 무시한다.
  func removePendingRequests(ids: Set<String>) async
}
