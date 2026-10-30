import Synchronization

/// 실행 하나의 저장소 출입문 (docs/ARCHITECTURE.md §4 인덱싱). 인덱서의 저장소 호출은 모두 이 문을 거친다(`IndexingRun.store`).
/// 실행을 멈추면 문을 닫는다(되돌리지 않는다. 다시 돌 때는 새 실행·새 문). 닫힌 문은 새 호출을 거절하고, `drained()` 는 진행 중 호출이
/// 끝날 때까지 기다린다. 그래서 Vision 이 취소에 늦게 응답해도 "멈춘 뒤 진행 중 저장이 끝나면 그 실행은 저장소를 부르지 않음"이 지켜지고,
/// 실행 Task 의 끝을 기다리지 않아 앱이 뒤로 갈 때의 빌린 시간·BG 작업 만료 유예 안에 끝난다.
final class StoreGate: Sendable {
  private struct State {
    var isClosed = false
    var inFlight = 0
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())
  private let onWrite: @Sendable () -> Void

  /// - Parameter onWrite: 쓰기 호출이 성공할 때마다 부른다(BG 실행이 저장소를 바꿨는지, 위젯 갱신 요청 조건).
  init(onWrite: @escaping @Sendable () -> Void = {}) {
    self.onWrite = onWrite
  }

  /// 저장소를 부르기 전에 부른다. 닫혔으면 false(부르지 않는다).
  func enter() -> Bool {
    self.state.withLock { state in
      guard !state.isClosed else { return false }
      state.inFlight += 1
      return true
    }
  }

  /// `enter()` 가 true 였던 호출이 끝나면 부른다.
  func exit() {
    let waiters = self.state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.inFlight -= 1
      return Self.takeWaitersIfDrained(&state)
    }
    waiters.forEach { $0.resume() }
  }

  /// 문을 닫는다. 그 뒤 `enter()` 는 false 다.
  func close() {
    let waiters = self.state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.isClosed = true
      return Self.takeWaitersIfDrained(&state)
    }
    waiters.forEach { $0.resume() }
  }

  var isClosed: Bool {
    self.state.withLock(\.isClosed)
  }

  /// 닫혔고 진행 중 호출이 없을 때까지 기다린다. 취소를 받지 않는다: 저장소 호출은 짧고 반드시 끝나며,
  /// 기다리는 쪽(앱이 뒤로 갈 때·BG 만료)은 그 끝을 보장해야 저장소에서 손을 뗐다고 볼 수 있다.
  func drained() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let resumesNow = self.state.withLock { state in
        guard !(state.isClosed && state.inFlight == 0) else { return true }
        state.waiters.append(continuation)
        return false
      }
      if resumesNow {
        continuation.resume()
      }
    }
  }

  /// 쓰기 호출이 성공했다.
  func didWrite() {
    self.onWrite()
  }

  private static func takeWaitersIfDrained(_ state: inout State) -> [CheckedContinuation<Void, Never>] {
    guard state.isClosed, state.inFlight == 0 else { return [] }
    defer { state.waiters = [] }
    return state.waiters
  }
}
