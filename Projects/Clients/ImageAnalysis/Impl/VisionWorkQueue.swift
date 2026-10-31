import Dispatch
import Synchronization

/// 직렬 큐 하나에서 동기 작업을 차례로 돌린다. 부른 Task 가 취소되면 작업을 기다리지 않고 바로 `CancellationError` 를 던진다.
/// 아직 시작하지 않은 작업은 시작할 때 취소를 보고 body 를 부르지 않는다. 이미 시작한 작업은 끝까지 돌고 결과는 버린다
/// (공유 요청에 `VNRequest.cancel()` 을 부르지 않는다: 그 사이 다음 호출의 작업이 시작됐으면 남의 요청을 멈출 수 있다).
/// 작업이 시작하면 시한 타이머를 건다(큐를 기다린 시간은 세지 않는다). 타이머는 큐가 쥐어 부른 쪽이 먼저 돌아가도 터진다.
/// 시한 안에 끝나지 않으면 큐를 버린다(종단): 기다리던 부른 쪽은 `Failure.timedOut`, 줄 선 호출과 그 뒤 새 호출은 `Failure.abandoned` 다.
/// QoS 는 1단계가 도는 Task 와 같은 급(`.userInitiated`)이다.
final class VisionWorkQueue: Sendable {
  enum Failure: Error, Equatable {
    /// 이 작업이 시한을 넘겼다.
    case timedOut
    /// 큐가 버려져 이 작업을 돌리지 않았다.
    case abandoned
  }

  /// 시한이 터졌을 때의 상태.
  struct TimeoutInfo: Sendable, Equatable {
    /// 그 작업을 부른 쪽이 아직 기다리고 있었는지. false 면 이미 취소로 돌아갔다.
    let isCallerWaiting: Bool
    /// 줄 서 있다 `.abandoned` 로 푼 호출 수.
    let releasedWaiting: Int
  }

  /// 큐에서 생긴 일마다 부르는 것. 모두 큐 잠금 밖에서 부른다.
  struct Hooks: Sendable {
    /// 줄에 넣은 직후. 버린 큐라 넣지 않았으면 부르지 않는다.
    var enqueued: @Sendable () -> Void = {}
    /// 작업이 시작할 때. 부른 쪽이 이미 돌아갔어도(취소) 시작한 작업이면 부른다.
    var started: @Sendable () -> Void = {}
    /// body 가 실제로 돌아왔을 때(늦어도). `afterTimeout` 은 시한이 이미 터진 뒤였는지다.
    var ended: @Sendable (_ afterTimeout: Bool) -> Void = { _ in }
    /// 시한이 터졌을 때 한 번. 기다리던 부른 쪽과 줄 선 호출을 풀기 전에 부른다(먼저 세대를 버리게).
    var timedOut: @Sendable (TimeoutInfo) -> Void = { _ in }
  }

  /// 시한 타이머를 거는 함수. 받은 시간 뒤에 클로저를 부른다. 테스트가 바꾼다.
  typealias Schedule = @Sendable (Duration, @escaping @Sendable () -> Void) -> Void

  /// 실행 중인 작업.
  private struct Running {
    let id: Int
    let isCallerWaiting: @Sendable () -> Bool
    let release: @Sendable (Failure) -> Void
    let hooks: Hooks
  }

  /// 시한이 터진 작업과 풀 대기 호출.
  private struct Expired {
    let running: Running
    let released: [@Sendable (Failure) -> Void]
    let isCallerWaiting: Bool
  }

  private struct State {
    var isAbandoned = false
    var nextID = 0
    /// 아직 시작하지 않은 호출의 풀기 함수.
    var waiting: [Int: @Sendable (Failure) -> Void] = [:]
    var running: Running?
  }

  private let queue: DispatchQueue
  private let schedule: Schedule
  private let state = Mutex(State())

  /// - Parameter schedule: 시한 타이머. 기본은 global 큐의 `asyncAfter` 다(이 큐는 막혀 있을 수 있어 쓰지 않는다).
  init(label: String, schedule: @escaping Schedule = VisionWorkQueue.dispatchAfter) {
    self.queue = DispatchQueue(label: label, qos: .userInitiated)
    self.schedule = schedule
  }

  static let dispatchAfter: Schedule = { delay, work in
    let (seconds, attoseconds) = delay.components
    let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(nanoseconds), execute: work)
  }

  /// 시한으로 버렸는지. 버린 큐는 다시 쓰이지 않는다.
  var isAbandoned: Bool {
    self.state.withLock(\.isAbandoned)
  }

  /// - Parameter timeout: 이 작업의 시한. 작업이 시작할 때부터 센다.
  func run<T: Sendable>(
    timeout: Duration,
    hooks: Hooks = Hooks(),
    _ body: @escaping @Sendable () throws -> T
  ) async throws -> T {
    let handoff = VisionWorkHandoff<T>()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard handoff.install(continuation) else {
          return
        }
        let id: Int? = self.state.withLock { state in
          guard !state.isAbandoned else {
            return nil
          }
          let id = state.nextID
          state.nextID += 1
          state.waiting[id] = { handoff.finish(.failure($0)) }
          return id
        }
        guard let id else {
          handoff.finish(.failure(Failure.abandoned))
          return
        }
        hooks.enqueued()
        self.queue.async {
          self.start(id, timeout: timeout, hooks: hooks, handoff: handoff, body: body)
        }
      }
    } onCancel: {
      handoff.finish(.failure(CancellationError()))
    }
  }

  /// 큐에서 차례가 온 작업. 버린 큐이거나 부른 쪽이 이미 돌아갔으면 body 를 부르지 않는다.
  private func start<T: Sendable>(
    _ id: Int,
    timeout: Duration,
    hooks: Hooks,
    handoff: VisionWorkHandoff<T>,
    body: @Sendable () throws -> T
  ) {
    // 잠금 순서: 큐 잠금 → handoff 잠금.
    let begins = self.state.withLock { state in
      guard !state.isAbandoned, state.waiting.removeValue(forKey: id) != nil, handoff.begin() else {
        return false
      }
      state.running = Running(
        id: id,
        isCallerWaiting: { handoff.isWaiting },
        release: { handoff.finish(.failure($0)) },
        hooks: hooks
      )
      return true
    }
    guard begins else {
      return
    }
    self.schedule(timeout) {
      self.expire(id)
    }
    hooks.started()
    let result = Result { try body() }
    let afterTimeout = self.state.withLock { state in
      guard state.running?.id == id else {
        return true
      }
      state.running = nil
      return false
    }
    hooks.ended(afterTimeout)
    // 시한 뒤면 handoff 는 이미 끝나 있어 결과는 버려진다.
    handoff.finish(result)
  }

  /// 시한 타이머. 그 작업이 아직 돌고 있으면 큐를 버리고, 훅을 부른 뒤 부른 쪽과 줄 선 호출을 푼다.
  /// 시한 안에 끝났으면 아무것도 하지 않는다(타이머를 취소하지 않고 이 확인으로 무시한다).
  private func expire(_ id: Int) {
    let expired = self.state.withLock { state -> Expired? in
      guard let running = state.running, running.id == id else {
        return nil
      }
      state.running = nil
      state.isAbandoned = true
      let released = Array(state.waiting.values)
      state.waiting = [:]
      return Expired(running: running, released: released, isCallerWaiting: running.isCallerWaiting())
    }
    guard let expired else {
      return
    }
    expired.running.hooks.timedOut(TimeoutInfo(
      isCallerWaiting: expired.isCallerWaiting,
      releasedWaiting: expired.released.count
    ))
    expired.running.release(.timedOut)
    expired.released.forEach { $0(.abandoned) }
  }
}

/// `VisionWorkQueue.run` 의 기다림 상태. continuation 을 한 번만 재개한다.
private final class VisionWorkHandoff<Output: Sendable>: Sendable {
  private struct State {
    var continuation: CheckedContinuation<Output, any Error>?
    /// continuation 을 받기 전에 끝난 결과(부른 Task 가 이미 취소됨).
    var early: Result<Output, any Error>?
    var isFinished = false
  }

  private let state = Mutex(State())

  /// 부른 쪽이 아직 결과를 기다리는지.
  var isWaiting: Bool {
    self.state.withLock { !$0.isFinished }
  }

  /// continuation 을 받는다. 이미 끝났으면 바로 재개하고 false(작업을 넣지 않는다).
  func install(_ continuation: CheckedContinuation<Output, any Error>) -> Bool {
    let early: Result<Output, any Error>? = self.state.withLock { state in
      if let early = state.early {
        return early
      }
      state.continuation = continuation
      return nil
    }
    if let early {
      continuation.resume(with: early)
      return false
    }
    return true
  }

  /// 큐에서 작업을 시작할 때 부른다. 이미 끝났으면(취소) false 다.
  func begin() -> Bool {
    self.isWaiting
  }

  /// 처음 온 결과만 쓴다. 늦게 온 결과는 버린다.
  func finish(_ result: Result<Output, any Error>) {
    let continuation = self.state.withLock { state -> CheckedContinuation<Output, any Error>? in
      guard !state.isFinished else {
        return nil
      }
      state.isFinished = true
      guard let continuation = state.continuation else {
        state.early = result
        return nil
      }
      state.continuation = nil
      return continuation
    }
    continuation?.resume(with: result)
  }
}
