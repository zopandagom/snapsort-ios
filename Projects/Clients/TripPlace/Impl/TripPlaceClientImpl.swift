import Core
import Foundation
import MapInterface
import PhotoStoreInterface
import TripPlaceInterface

/// 저장된 여행 중심점의 장소 이름을 미리 받는 구현 (docs/ARCHITECTURE.md §4 위치·지도 원칙 ①).
/// Map·PhotoStore Interface 를 조합하고 Apple 프레임워크를 직접 쓰지 않는다. 보내는 값은 반올림 중심점과 로캘뿐이다.
/// 요청은 한 번에 하나(상세 요청과는 따로), 요청 사이 간격을 두고, 실패·시한이면 회차를 멈추고 최소 간격 뒤에 다시 묻는다.
/// 시한을 넘긴 요청이 돌아오지 않은 동안은 새 요청을 내지 않는다(오프라인 요청 누적 방지).
/// 상태는 앱 실행 동안 하나라 App 이 하나만 만든다. 좌표·장소 이름은 로그에 남기지 않는다.
public actor TripPlaceClientImpl: TripPlaceClient {
  typealias Now = @Sendable () -> ContinuousClock.Instant
  typealias Sleep = @Sendable (TripPlaceSleep, Duration) async throws -> Void

  let map: any MapClient
  let photoStore: any PhotoStoreClient
  private let policy: TripPlacePolicy
  let now: Now
  let sleep: Sleep
  private let isLowPowerMode: @Sendable () -> Bool

  /// 회차 진행 중. 참이면 새 회차는 바로 돌아온다. 첫 await 전에 세우고 회차가 끝날 때 내린다.
  private var isRunning = false
  /// 나간 요청(최대 1). 요청 Task 가 끝날 때 번호가 같으면 비운다.
  private var outstanding: TripPlaceOutstanding?
  /// 이 시각 전엔 회차가 바로 돌아온다. 시한으로 건 쉼은 그 요청 번호를 담아, 그 요청이 늦게라도 성공하면 푼다.
  private var cooldown: (until: ContinuousClock.Instant, token: Int?)?
  /// 마지막 요청이 끝난 시각(성공·실패·늦은 응답 모두). 다음 요청은 이것에 간격을 더한 뒤다(회차를 넘어).
  private var lastRequestEndedAt: ContinuousClock.Instant?
  /// 항목 없음을 받은 요청. 캐시에 쓰지 않으므로 같은 실행 동안 다시 묻지 않게 메모리에만 둔다.
  private var notFound: Set<TripPlaceRequest> = []
  private var nextToken = 0
  private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

  public init(map: any MapClient, photoStore: any PhotoStoreClient) {
    self.init(
      map: map,
      photoStore: photoStore,
      policy: TripPlacePolicy(),
      now: { .now },
      sleep: { _, duration in try await Task.sleep(for: duration) },
      isLowPowerMode: { ProcessInfo.processInfo.isLowPowerModeEnabled }
    )
  }

  /// 테스트가 정책 값·시계·수면·저전력 모드를 주입한다. `now` 는 기기 잠자기·앱 정지 동안에도 흐르는 시계여야 한다.
  init(
    map: any MapClient,
    photoStore: any PhotoStoreClient,
    policy: TripPlacePolicy,
    now: @escaping Now,
    sleep: @escaping Sleep,
    isLowPowerMode: @escaping @Sendable () -> Bool
  ) {
    self.map = map
    self.photoStore = photoStore
    self.policy = policy
    self.now = now
    self.sleep = sleep
    self.isLowPowerMode = isLowPowerMode
  }

  public func prefetchPlaces(locale: Locale) async {
    guard !self.isRunning else { return }
    self.isRunning = true
    defer { self.isRunning = false }
    guard await self.canStartRound() else { return }
    let localeIdentifier = locale.identifier
    guard let targets = await self.targets(localeIdentifier: localeIdentifier) else { return }
    for key in targets {
      guard await self.waitForInterval() else { return }
      switch await self.isStillMissing(key, localeIdentifier: localeIdentifier) {
      case nil: return
      case false?: continue
      case true?: break
      }
      let started = self.startRequest(TripPlaceRequest(key: key, localeIdentifier: localeIdentifier))
      let result = await self.first(of: started.task, timeout: self.policy.timeout)
      guard self.shouldContinue(after: result, token: started.token) else { return }
    }
  }

  // MARK: - 회차 단계

  /// 저전력 모드·쉼 중이 아니고 앞 회차의 남은 요청도 이어 가도 되면 true.
  private func canStartRound() async -> Bool {
    guard !self.isLowPowerMode(), !self.isCoolingDown else { return false }
    if let outstanding, await !(self.awaitOutstanding(outstanding)) {
      return false
    }
    return true
  }

  /// 앞 회차에서 남은 요청을 시한 안에서 마저 기다린다. 이어 가도 되면 true.
  /// 시한을 이미 넘긴 요청이면 기다리지 않고 false 다(돌아오지 않은 동안 새 요청을 내지 않는다).
  private func awaitOutstanding(_ outstanding: TripPlaceOutstanding) async -> Bool {
    let remaining = outstanding.startedAt + self.policy.timeout - self.now()
    guard remaining > .zero else { return false }
    let result = await self.first(of: outstanding.task, timeout: remaining)
    return self.shouldContinue(after: result, token: outstanding.token)
  }

  /// 이번 회차에 물을 키: 최신 여행부터, 같은 키는 한 번, 이 로캘 이름(`.named`·`.unnamed`)이 캐시에 없고
  /// 항목 없음을 받지 않은 것을 상한까지. 저장소를 읽지 못하거나 부른 Task 가 취소되면 nil(요청을 내지 않았으니 쉼도 두지 않는다).
  private func targets(localeIdentifier: String) async -> [RoundedCoordinate]? {
    guard let trips = try? await self.photoStore.trips(), !Task.isCancelled else { return nil }
    // 저장소는 시작↑·끝↑ 순이라 뒤집으면 여행 목록과 같은 최신순이다.
    var seen: Set<RoundedCoordinate> = []
    let keys = trips.reversed().compactMap(\.placeKey).filter { seen.insert($0).inserted }
    guard !keys.isEmpty else { return [] }
    guard let cached = try? await self.photoStore.places(for: Set(keys), localeIdentifier: localeIdentifier),
          !Task.isCancelled
    else {
      return nil
    }
    let missing = keys.filter { key in
      cached[key]?.name == nil && !self.notFound.contains(TripPlaceRequest(
        key: key,
        localeIdentifier: localeIdentifier
      ))
    }
    return Array(missing.prefix(self.policy.roundLimit))
  }

  /// 마지막 요청이 끝난 뒤 간격이 지나도록 기다린다. 부른 Task 가 취소되면 false.
  private func waitForInterval() async -> Bool {
    if let lastRequestEndedAt {
      let wait = lastRequestEndedAt + self.policy.requestInterval - self.now()
      if wait > .zero {
        do {
          try await self.sleep(.interval, wait)
        } catch {
          return false
        }
      }
    }
    return !Task.isCancelled
  }

  /// 묻기 직전에 캐시를 다시 본다(그사이 상세가 받았을 수 있다). 아직 이름이 없으면 true, 생겼으면 false,
  /// 읽지 못하거나 부른 Task 가 취소되면 nil.
  private func isStillMissing(_ key: RoundedCoordinate, localeIdentifier: String) async -> Bool? {
    guard let cached = try? await self.photoStore.places(for: [key], localeIdentifier: localeIdentifier),
          !Task.isCancelled
    else {
      return nil
    }
    return cached[key]?.name == nil
  }

  /// 요청 결과·시한·취소에 따라 회차를 이어 갈지 정한다. 시한이면 그 요청 번호로 쉼을 건다.
  /// 실패의 쉼은 요청 Task 가 끝날 때 건다(회차가 기다리지 않던 늦은 실패도 같게).
  /// 시한과 응답이 엇갈려 이 판단 전에 요청이 이미 끝났으면(`finishRequest` 가 먼저 돎) 쉼을 새로 걸지 않고 그 결과를 따른다:
  /// 실패였으면 `finishRequest` 가 건 쉼이 있어 멈추고, 성공이면 이어 간다. 테스트가 이 순서를 직접 부른다.
  func shouldContinue(after result: TripPlaceRaceResult?, token: Int) -> Bool {
    switch result {
    case .response(.saved), .response(.tripGone), .response(.notFound):
      return true
    case .response(.failed), .response(.saveFailed):
      return false
    case .timedOut:
      guard self.outstanding?.token == token else {
        return !self.isCoolingDown
      }
      self.cooldown = (until: self.now() + self.policy.failureCooldown, token: token)
      return false
    case nil:
      return false
    }
  }

  /// 실패·시한 뒤 최소 간격이 아직 지나지 않았는지.
  private var isCoolingDown: Bool {
    guard let cooldown else { return false }
    return self.now() < cooldown.until
  }

  // MARK: - 요청 상태 (TripPlaceRequestRun)

  /// 나간 요청이 남아 있는지. 회차가 기다리지 않는 늦은 응답이 처리됐는지 테스트가 확인한다.
  var hasOutstandingRequest: Bool {
    self.outstanding != nil
  }

  func issueToken() -> Int {
    defer { self.nextToken += 1 }
    return self.nextToken
  }

  func setOutstanding(_ outstanding: TripPlaceOutstanding) {
    self.outstanding = outstanding
  }

  /// 요청 Task 가 끝날 때 부른다. 실패면 쉼을 건다(이미 그 요청의 시한 쉼이 걸려 있으면 그대로 둔다).
  /// 시한으로 건 쉼은 그 요청이 늦게라도 응답을 받으면 푼다.
  func finishRequest(_ request: TripPlaceRequest, token: Int, outcome: TripPlaceRequestOutcome) {
    self.lastRequestEndedAt = self.now()
    if self.outstanding?.token == token {
      self.outstanding = nil
    }
    let ownsCooldown = self.cooldown?.token == token
    switch outcome {
    case .saved, .tripGone, .notFound:
      if ownsCooldown {
        self.cooldown = nil
      }
    case .failed, .saveFailed:
      if !ownsCooldown {
        self.cooldown = (until: self.now() + self.policy.failureCooldown, token: nil)
      }
    }
    if outcome == .notFound {
      self.notFound.insert(request)
    }
    if outcome == .saved {
      for continuation in self.subscribers.values {
        continuation.yield()
      }
    }
  }

  // MARK: - 변경 신호

  public func placeChanges() async -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(id) }
    }
    self.subscribers[id] = continuation
    return stream
  }

  private func removeSubscriber(_ id: UUID) {
    self.subscribers[id] = nil
  }
}
