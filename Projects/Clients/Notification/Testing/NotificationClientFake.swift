import Core
import NotificationInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 메모리에 대기 알림을 두어 Impl 처럼 추가·삭제가 조회에 반영되고, 권한 요청·추가·삭제·설정 열기를 기록한다.
/// 실제 알림 센터처럼 권한 요청 뒤 상태가 바뀌고 예약이 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class NotificationClientFake: NotificationClient {
  private let authorizationAfterRequest: NotificationAuthorization?
  private let failingAddIDs: Set<String>
  private let onAuthorizationStatus: @Sendable (Int) async -> Void
  private let onRequestAuthorization: @Sendable () async -> Void
  private let onPendingRequestIDs: @Sendable (Int) async -> Void
  private let state: Mutex<State>

  private struct State {
    var authorization: NotificationAuthorization
    var pending: [String: NotificationRequest]
    var authorizationStatusCount = 0
    var pendingRequestIDsCount = 0
    var requestAuthorizationCount = 0
    var addAttemptCount = 0
    var addedBatches: [[NotificationRequest]] = []
    var removedBatches: [Set<String>] = []
    var openSettingsCount = 0
  }

  /// - Parameters:
  ///   - authorization: 처음 권한 상태.
  ///   - authorizationAfterRequest: `requestAuthorization()` 뒤의 상태. nil 이면 요청해도 그대로다.
  ///   - pending: 처음 대기 알림.
  ///   - failingAddIDs: `add` 가 이 식별자들만 건너뛰고 나머지는 넣은 뒤 `.failed` 를 던진다. Impl 처럼 실패한 것만 빠진다.
  ///   - onAuthorizationStatus: `authorizationStatus()` 가 상태를 읽은 뒤 돌려주기 전에 기다려 부른다. 인자는 몇 번째 호출인지(0부터)다.
  ///     권한 요청과 겹친 동기화가 요청 전 값을 읽고 요청이 끝난 뒤 돌아오는 순서를 흉내 낸다. 호출 번호로 붙잡을 호출만 고른다.
  ///   - onRequestAuthorization: `requestAuthorization()` 이 상태를 바꾸기 전에 기다려 부른다. 팝업이 떠 있는 동안을 흉내 낸다.
  ///   - onPendingRequestIDs: `pendingRequestIDs()` 가 식별자를 읽은 뒤 돌려주기 전에 기다려 부른다. 인자는 몇 번째 호출인지(0부터)다.
  ///     기다리는 동안 대기 알림이 바뀌어도 앞서 읽은 값을 돌려줘, 늦게 깨어난 동기화를 흉내 낸다.
  public init(
    authorization: NotificationAuthorization = .authorized,
    authorizationAfterRequest: NotificationAuthorization? = nil,
    pending: [NotificationRequest] = [],
    failingAddIDs: Set<String> = [],
    onAuthorizationStatus: @escaping @Sendable (Int) async -> Void = { _ in },
    onRequestAuthorization: @escaping @Sendable () async -> Void = {},
    onPendingRequestIDs: @escaping @Sendable (Int) async -> Void = { _ in }
  ) {
    self.authorizationAfterRequest = authorizationAfterRequest
    self.failingAddIDs = failingAddIDs
    self.onAuthorizationStatus = onAuthorizationStatus
    self.onRequestAuthorization = onRequestAuthorization
    self.onPendingRequestIDs = onPendingRequestIDs
    self.state = Mutex(State(
      authorization: authorization,
      pending: Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    ))
  }

  /// 지금 권한 상태.
  public var authorization: NotificationAuthorization {
    self.state.withLock { $0.authorization }
  }

  /// 지금 대기 알림. 식별자 순이다.
  public var pendingRequests: [NotificationRequest] {
    self.state.withLock { $0.pending.values.sorted { $0.id < $1.id } }
  }

  /// `authorizationStatus()` 를 부른 횟수.
  public var authorizationStatusCount: Int {
    self.state.withLock { $0.authorizationStatusCount }
  }

  /// `requestAuthorization()` 을 부른 횟수.
  public var requestAuthorizationCount: Int {
    self.state.withLock { $0.requestAuthorizationCount }
  }

  /// `add` 를 부른 횟수. 실패한 호출도 센다.
  public var addAttemptCount: Int {
    self.state.withLock { $0.addAttemptCount }
  }

  /// `add` 호출마다 실제로 넣은 요청을 부른 순서대로.
  public var addedBatches: [[NotificationRequest]] {
    self.state.withLock { $0.addedBatches }
  }

  /// `removePendingRequests` 에 넘긴 식별자를 부른 순서대로.
  public var removedBatches: [Set<String>] {
    self.state.withLock { $0.removedBatches }
  }

  /// `openSettings()` 를 부른 횟수.
  public var openSettingsCount: Int {
    self.state.withLock { $0.openSettingsCount }
  }

  public func authorizationStatus() async -> NotificationAuthorization {
    let (authorization, index) = self.state.withLock { state in
      defer { state.authorizationStatusCount += 1 }
      return (state.authorization, state.authorizationStatusCount)
    }
    await self.onAuthorizationStatus(index)
    return authorization
  }

  public func requestAuthorization() async -> NotificationAuthorization {
    self.state.withLock { $0.requestAuthorizationCount += 1 }
    await self.onRequestAuthorization()
    return self.state.withLock { state in
      if let authorization = self.authorizationAfterRequest {
        state.authorization = authorization
      }
      return state.authorization
    }
  }

  public func pendingRequestIDs() async -> Set<String> {
    let (ids, index) = self.state.withLock { state in
      defer { state.pendingRequestIDsCount += 1 }
      return (Set(state.pending.keys), state.pendingRequestIDsCount)
    }
    await self.onPendingRequestIDs(index)
    return ids
  }

  public func add(_ requests: [NotificationRequest]) async throws(NotificationError) {
    let added = requests.filter { !self.failingAddIDs.contains($0.id) }
    self.state.withLock { state in
      state.addAttemptCount += 1
      state.addedBatches.append(added)
      for request in added {
        state.pending[request.id] = request
      }
    }
    if added.count != requests.count {
      throw .failed
    }
  }

  public func removePendingRequests(ids: Set<String>) async {
    self.state.withLock { state in
      state.removedBatches.append(ids)
      for id in ids {
        state.pending[id] = nil
      }
    }
  }

  public func openSettings() async {
    self.state.withLock { $0.openSettingsCount += 1 }
  }
}
