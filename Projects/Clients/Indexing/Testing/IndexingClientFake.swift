import IndexingInterface
import Synchronization

/// 테스트와 Example 앱용 대역. `run()` 마다 정해 둔 진행률을 차례로 보낸다.
/// 실제처럼 구독을 끝낼 때까지 이어지게 할 수 있고, 그동안 진행률을 더 보내거나 스트림을 끝내 인덱싱이 멈춘 것을 흉내 낼 수 있다.
/// 지금 돌고 있는 `run()` 과 지금까지 부른 `run()` 을 센다.
/// BG 작업 쪽(`appActivityChanged`·`waitUntilStoreReleased`·`runInBackground`)은 호출을 순서대로 기록하고(`events`, `onEvent`),
/// 정해 둔 결과를 바로 돌려주거나 테스트가 끝낼 때까지 기다린다.
/// 구독이 끝났는지 호출 사이에 기록해야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class IndexingClientFake: IndexingClient {
  /// BG 작업 쪽 호출 기록. 여러 대역의 호출 순서를 함께 보려면 `onEvent` 로 한곳에 모은다.
  public enum Event: Sendable, Equatable {
    case appActivityChanged(isActive: Bool)
    /// `waitUntilStoreReleased()` 를 불렀다.
    case waitUntilStoreReleasedStarted
    /// `waitUntilStoreReleased()` 가 돌아왔다.
    case waitUntilStoreReleasedReturned
    /// `runInBackground` 를 불렀다.
    case runInBackgroundStarted
    /// `runInBackground` 를 부른 Task 가 취소됐다.
    case runInBackgroundCancelled
    /// `runInBackground` 가 돌아왔다.
    case runInBackgroundReturned(IndexingBackgroundResult)
  }

  public let progress: [IndexingProgress]
  private let finishesAfterProgress: Bool
  private let backgroundProgress: [IndexingProgress]
  private let backgroundResult: IndexingBackgroundResult?
  private let holdsStoreRelease: Bool
  private let onEvent: @Sendable (Event) -> Void
  private let state = Mutex(State())

  private struct State {
    var runCount = 0
    var runs: [Int: AsyncStream<IndexingProgress>.Continuation] = [:]
    var events: [Event] = []
    var nextHoldID = 0
    var holds: [Int: BackgroundHold] = [:]
    var lastShouldYield: (@Sendable () -> Bool)?
    var storeReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    var isStoreReleaseHeld = false
    /// continuation 을 받기 전에 정해진 결과.
    var earlyResults: [Int: IndexingBackgroundResult] = [:]
  }

  /// 기다리는 `runInBackground` 하나.
  private struct BackgroundHold {
    var continuation: CheckedContinuation<IndexingBackgroundResult, Never>?
    let progress: @Sendable (IndexingProgress) -> Void
  }

  /// - Parameter finishesAfterProgress: 참이면 진행률을 다 보낸 뒤 스트림을 끝낸다.
  ///   거짓이면 실제처럼 받는 쪽이 구독을 끝낼 때(Task 취소)나 `finishRuns()` 까지 이어진다.
  /// - Parameter backgroundProgress: `runInBackground` 가 `progress` 로 차례로 보낼 진행률.
  /// - Parameter backgroundResult: `runInBackground` 가 진행률을 보낸 뒤 돌려줄 결과. nil 이면 `finishBackgroundRuns(with:)` 나
  ///   부른 Task 의 취소(`(true, false)`)까지 기다린다.
  /// - Parameter holdsStoreRelease: 참이면 `waitUntilStoreReleased()` 가 `releaseStore()` 까지 기다린다.
  /// - Parameter onEvent: BG 작업 쪽 호출마다 기록과 같은 순서로 부른다.
  public init(
    progress: [IndexingProgress] = [],
    finishesAfterProgress: Bool = true,
    backgroundProgress: [IndexingProgress] = [],
    backgroundResult: IndexingBackgroundResult? = IndexingBackgroundResult(
      hasRemainingWork: false,
      didChangeStore: false
    ),
    holdsStoreRelease: Bool = false,
    onEvent: @escaping @Sendable (Event) -> Void = { _ in }
  ) {
    self.progress = progress
    self.finishesAfterProgress = finishesAfterProgress
    self.backgroundProgress = backgroundProgress
    self.backgroundResult = backgroundResult
    self.holdsStoreRelease = holdsStoreRelease
    self.onEvent = onEvent
    self.state.withLock { $0.isStoreReleaseHeld = holdsStoreRelease }
  }

  /// 아직 끝나지 않은 `run()` 스트림 수.
  public var activeRunCount: Int {
    self.state.withLock { $0.runs.count }
  }

  /// 지금까지 `run()` 을 부른 횟수. 멈춘 인덱싱을 다시 시작했는지 확인하는 데 쓴다.
  public var runCount: Int {
    self.state.withLock { $0.runCount }
  }

  /// BG 작업 쪽 호출을 부른 순서대로.
  public var events: [Event] {
    self.state.withLock { $0.events }
  }

  /// `appActivityChanged(isActive:)` 에 넘긴 값을 부른 순서대로.
  public var activityChanges: [Bool] {
    self.events.compactMap { event in
      guard case let .appActivityChanged(isActive) = event else { return nil }
      return isActive
    }
  }

  /// 아직 돌아오지 않은 `runInBackground` 수.
  public var activeBackgroundRunCount: Int {
    self.state.withLock { $0.holds.count }
  }

  /// 마지막 `runInBackground` 에 넘긴 `shouldYield` 를 지금 불러 본 값. 부른 적이 없으면 nil.
  public var lastShouldYield: Bool? {
    self.state.withLock { $0.lastShouldYield }?()
  }

  public func run() -> AsyncStream<IndexingProgress> {
    let (stream, continuation) = AsyncStream.makeStream(of: IndexingProgress.self)
    let id = self.state.withLock { state in
      let id = state.runCount
      state.runCount += 1
      return id
    }
    // 정리 핸들러를 먼저 달고 등록한다. 등록 뒤에 달면 그 사이 `finishRuns()` 로 끝난 스트림이 목록에 남는다.
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { _ = $0.runs.removeValue(forKey: id) }
    }
    self.state.withLock { $0.runs[id] = continuation }
    for progress in self.progress {
      continuation.yield(progress)
    }
    if self.finishesAfterProgress {
      continuation.finish()
    }
    return stream
  }

  public func appActivityChanged(isActive: Bool) {
    self.record(.appActivityChanged(isActive: isActive))
  }

  /// `holdsStoreRelease` 면 `releaseStore()` 까지 기다린다. 실제처럼 취소를 받지 않는다.
  public func waitUntilStoreReleased() async {
    self.record(.waitUntilStoreReleasedStarted)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let resumesNow = self.state.withLock { state in
        guard state.isStoreReleaseHeld else { return true }
        state.storeReleaseWaiters.append(continuation)
        return false
      }
      if resumesNow {
        continuation.resume()
      }
    }
    self.record(.waitUntilStoreReleasedReturned)
  }

  /// 정해 둔 진행률을 `progress` 로 보낸 뒤 정해 둔 결과를 돌려준다. 결과를 정하지 않았으면 `finishBackgroundRuns(with:)` 까지 기다리고,
  /// 그동안 `sendBackgroundProgress(_:)` 로 진행률을 더 보낼 수 있다. 부른 Task 가 취소되면 `(true, false)` 로 돌아온다.
  public func runInBackground(
    shouldYield: @escaping @Sendable () -> Bool,
    progress: @escaping @Sendable (IndexingProgress) -> Void
  ) async -> IndexingBackgroundResult {
    let id = self.state.withLock { state in
      state.lastShouldYield = shouldYield
      state.events.append(.runInBackgroundStarted)
      defer { state.nextHoldID += 1 }
      state.holds[state.nextHoldID] = BackgroundHold(continuation: nil, progress: progress)
      return state.nextHoldID
    }
    self.onEvent(.runInBackgroundStarted)
    for value in self.backgroundProgress {
      progress(value)
    }
    let result: IndexingBackgroundResult
    if let backgroundResult {
      result = backgroundResult
      self.state.withLock { _ = $0.holds.removeValue(forKey: id) }
    } else {
      result = await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<IndexingBackgroundResult, Never>) in
          let early = self.state.withLock { state -> IndexingBackgroundResult? in
            if let early = state.earlyResults.removeValue(forKey: id) {
              return early
            }
            state.holds[id]?.continuation = continuation
            return nil
          }
          if let early {
            continuation.resume(returning: early)
          }
        }
      } onCancel: {
        self.record(.runInBackgroundCancelled)
        self.resumeHold(id, with: IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
      }
    }
    self.record(.runInBackgroundReturned(result))
    return result
  }

  // MARK: - 진행 흉내

  /// 돌고 있는 모든 `run()` 스트림에 진행률을 보낸다.
  public func sendProgress(_ progress: IndexingProgress) {
    for continuation in self.activeRuns() {
      continuation.yield(progress)
    }
  }

  /// 돌고 있는 모든 `run()` 스트림을 끝낸다. 저장소 실패 등으로 인덱싱이 중간에 멈춘 것을 흉내 낸다.
  public func finishRuns() {
    for continuation in self.activeRuns() {
      continuation.finish()
    }
  }

  /// 기다리는 모든 `runInBackground` 의 `progress` 로 진행률을 보낸다.
  public func sendBackgroundProgress(_ progress: IndexingProgress) {
    for send in self.state.withLock({ $0.holds.values.map(\.progress) }) {
      send(progress)
    }
  }

  /// 기다리는 모든 `runInBackground` 를 이 결과로 돌려보낸다.
  public func finishBackgroundRuns(with result: IndexingBackgroundResult) {
    for id in self.state.withLock({ Array($0.holds.keys) }) {
      self.resumeHold(id, with: result)
    }
  }

  /// 기다리는 `waitUntilStoreReleased()` 를 모두 돌려보내고, 그 뒤 부르는 것은 바로 돌아오게 한다.
  public func releaseStore() {
    let waiters = self.state.withLock { state in
      state.isStoreReleaseHeld = false
      defer { state.storeReleaseWaiters = [] }
      return state.storeReleaseWaiters
    }
    waiters.forEach { $0.resume() }
  }

  /// `finish()` 가 `onTermination` 을 불러 잠금을 다시 잡으므로, 잠금 밖에서 보내도록 복사해 둔다.
  private func activeRuns() -> [AsyncStream<IndexingProgress>.Continuation] {
    self.state.withLock { Array($0.runs.values) }
  }

  /// 기다리는 hold 를 빼고 잠금 밖에서 돌려보낸다. continuation 을 받기 전이면 결과를 두어 받을 때 바로 돌아오게 한다.
  private func resumeHold(_ id: Int, with result: IndexingBackgroundResult) {
    let continuation = self.state.withLock { state -> CheckedContinuation<IndexingBackgroundResult, Never>? in
      guard let hold = state.holds.removeValue(forKey: id) else { return nil }
      guard let continuation = hold.continuation else {
        state.earlyResults[id] = result
        return nil
      }
      return continuation
    }
    continuation?.resume(returning: result)
  }

  private func record(_ event: Event) {
    self.state.withLock { $0.events.append(event) }
    self.onEvent(event)
  }
}
