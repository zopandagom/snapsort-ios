import Foundation
import IndexingInterface
import Synchronization

/// 인덱서 실행 하나를 앞 구독자(`run()`)와 BG 작업(`runInBackground`)이 함께 쓰게 하는 공유 실행기 (docs/ARCHITECTURE.md §4 인덱싱).
/// 도는 조건은 (앱 활성 ∧ 앞 구독자 있음) ∨ BG 가 쥠이다. 조건이 깨지면 실행의 저장소 출입문을 닫고 Task 를 취소한다(멈춤).
/// 새 실행은 멈춘 실행들의 문이 손을 뗀 뒤(진행 중 저장소 호출이 끝난 뒤)에만 시작해, 저장소를 부르는 실행은 한 번에 하나다.
/// 취소에 늦게 응답하는 옛 실행(돌아오지 않는 Vision 요청)은 닫힌 문 때문에 저장소에 닿지 못하고, 그 진행률·유휴·끝은 무시한다.
/// BG 통계 기록과 저장소 쓰기 표시는 실행을 가리지 않는다. 멈춘 실행은 Task 가 취소되어 Vision·모델 결과가 취소가 되므로
/// (ImageAnalysis `VisionFailure`, Classifier 취소 규칙) 늦게 돌아온 요청의 실패로는 기록에 닿지 않는다. 남는 경로는 둘이다:
/// 문을 닫기 전에 들어간 저장의 장 수 기록과 쓰기 표시(실제로 저장소를 바꿨으므로 위젯 갱신 근거로 받는다), 그리고 모델 차단 중 미룸
/// (모델을 부르지 않고 바로 기록해 OCR 직후의 짧은 동기 구간에서 멈추면 닿는다. 그때 BG 가 한 번 더 예약될 뿐 저장 결과는 같다).
/// BG 작업이 도는 실행에 붙으면 그 실행의 최신 진행률을 그 hold 에 한 번 먼저 보낸다.
/// 앱이 비활성인 동안 앞 구독자에게 진행률을 보내지 않고 최신 값만 두었다가 다시 활성이 되면 한 번 보낸다(보관함 화면이 백그라운드에서
/// 저장소를 다시 읽지 않게). 비활성 중 실행이 스스로 끝나도 앞 구독자 스트림은 끝내지 않고 다시 활성이 될 때 새 실행으로 잇는다.
/// 상태는 Mutex 하나로 지키고, Task 취소·continuation 재개·진행률 전달은 잠금 밖에서 한다(취소 처리기가 잠금을 다시 잡지 않게).
final class IndexingExecutor: Sendable {
  typealias MakeRun = @Sendable (StoreGate, RunEnvironment) -> IndexingRun

  private let makeRun: MakeRun
  private let onAppActivityChanged: @Sendable (Bool) -> Void
  let isFeaturePrintAvailable: @Sendable () -> Bool
  private let state = Mutex(State())

  /// - Parameter onAppActivityChanged: 앱 활성 값이 바뀔 때 잠금 안에서 부른다(이미지 분석의 시한 차단·계산 장치). 받는 쪽은 자기 잠금만
  ///   쥐고 이 실행기를 부르지 않아야 한다(잠금 순서는 실행기 → 이미지 분석 한 방향).
  /// - Parameter isFeaturePrintAvailable: Debug 수치 로그에 남길 지금 벡터 사용 가능 여부.
  init(
    makeRun: @escaping MakeRun,
    onAppActivityChanged: @escaping @Sendable (Bool) -> Void,
    isFeaturePrintAvailable: @escaping @Sendable () -> Bool
  ) {
    self.makeRun = makeRun
    self.onAppActivityChanged = onAppActivityChanged
    self.isFeaturePrintAvailable = isFeaturePrintAvailable
  }

  // MARK: - 앞 구독

  func run() -> AsyncStream<IndexingProgress> {
    let (stream, continuation) = AsyncStream.makeStream(of: IndexingProgress.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.unsubscribe(id)
    }
    let effects = self.state.withLock { state -> Effects in
      state.subscribers[id] = continuation
      var effects = Effects()
      // 유휴 중인 실행에 붙어도 "분석 중"에 갇히지 않게 최신 값을 바로 보낸다.
      if state.isAppActive, let latest = state.current?.latest {
        effects.progressToSubscribers = (latest, [continuation])
      }
      self.reconcile(&state, &effects)
      return effects
    }
    effects.perform()
    return stream
  }

  private func unsubscribe(_ id: UUID) {
    let effects = self.state.withLock { state -> Effects in
      var effects = Effects()
      guard state.subscribers.removeValue(forKey: id) != nil else { return effects }
      self.reconcile(&state, &effects)
      return effects
    }
    effects.perform()
  }

  // MARK: - 앱 활성

  func appActivityChanged(isActive: Bool) {
    let effects = self.state.withLock { state -> Effects in
      var effects = Effects()
      // 같은 값이 다시 와도 앞 실행을 다시 시작하지 않는다.
      guard isActive != state.isAppActive else { return effects }
      state.isAppActive = isActive
      // 새 실행·다음 요청이 바뀐 값을 보도록 reconcile 전에 같은 잠금 안에서 알린다(받는 쪽은 자기 잠금만 쥔다).
      self.onAppActivityChanged(isActive)
      if isActive {
        // BG 모드로 돌던 실행은 멈추고 새 실행(전체 다시 비교)으로 이어 간다. BG 에서 미룬 것도 다시 시도한다.
        self.stopCurrent(&state, &effects)
        if let held = state.heldProgress {
          state.heldProgress = nil
          effects.progressToSubscribers = (held, Array(state.subscribers.values))
        }
      }
      self.reconcile(&state, &effects)
      return effects
    }
    effects.perform()
  }

  func waitUntilStoreReleased() async {
    let gates = self.state.withLock { $0.stopping.map(\.gate) }
    for gate in gates {
      await gate.drained()
    }
  }

  // MARK: - BG 작업

  func runInBackground(
    shouldYield: @escaping @Sendable () -> Bool,
    progress: @escaping @Sendable (IndexingProgress) -> Void
  ) async -> IndexingBackgroundResult {
    let id = UUID()
    let registered = self.state.withLock { state -> Effects? in
      // 앞 실행이 할 일을 마치고 쉬는 중이면 바로 돌아온다.
      if state.current?.isIdle == true {
        return nil
      }
      var effects = Effects()
      state.holds[id] = Hold(continuation: nil, shouldYield: shouldYield, progress: progress)
      self.reconcile(&state, &effects)
      // 도는 실행에 붙으면 최신 진행률을 이 hold 에 한 번 먼저 보낸다(계속 처리 작업이 시작하자마자 확정 진행률을 보이게).
      if let current = state.current, !current.isIdle, let latest = current.latest {
        effects.progressToHolds = (latest, [progress])
      }
      return effects
    }
    guard let registered else {
      return IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: false)
    }
    registered.perform()
    let outcome = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<HoldOutcome, Never>) in
        let early = self.state.withLock { state -> HoldOutcome? in
          if let early = state.earlyHoldOutcomes.removeValue(forKey: id) {
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
      self.cancelHold(id)
    }
    switch outcome {
    case let .finished(result):
      return result
    case let .cancelled(gate, didChangeStore):
      await gate?.drained()
      return IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: didChangeStore)
    }
  }

  /// BG 작업이 취소됐다. hold 를 빼고 비활성이면 실행을 멈춘다. 멈춘 실행의 문이 손을 뗄 때까지는 부른 쪽이 기다린다.
  private func cancelHold(_ id: UUID) {
    let effects = self.state.withLock { state -> Effects in
      var effects = Effects()
      guard let hold = state.holds[id] else { return effects }
      let gate = state.current?.gate
      self.reconcile(&state, &effects, removingHold: id)
      // 앱이 활성이면 실행은 앞 구독자가 이어 쥐어 문이 열려 있다. 그때는 기다리지 않는다.
      let gateToDrain = gate.flatMap { $0.isClosed ? $0 : nil }
      let ending = HoldEnding(
        outcome: .cancelled(gate: gateToDrain, didChangeStore: hold.didChangeStore),
        end: IndexingRunEnd.cancelled.rawValue
      )
      self.finishHold(id, hold, with: ending, &state, &effects)
      return effects
    }
    effects.perform()
    self.log(effects.logs)
  }

  // MARK: - 실행이 부르는 곳

  private func report(_ id: UUID, _ progress: IndexingProgress) {
    let effects = self.state.withLock { state -> Effects in
      var effects = Effects()
      guard state.current?.id == id else { return effects }
      state.current?.latest = progress
      state.current?.isIdle = false
      if state.isAppActive {
        effects.progressToSubscribers = (progress, Array(state.subscribers.values))
      } else {
        state.heldProgress = progress
      }
      effects.progressToHolds = (progress, state.holds.values.map(\.progress))
      return effects
    }
    effects.perform()
  }

  /// 실행이 할 일을 마치고 변경을 기다리기 직전. BG 가 쥔 것을 모두 돌려보내고, 비활성이면 실행을 멈춘다.
  /// 유휴 지점은 저장소 호출 밖이라 문을 닫는 즉시 손을 뗀 상태다.
  private func runIdle(_ id: UUID) {
    let effects = self.state.withLock { state -> Effects in
      var effects = Effects()
      guard state.current?.id == id else { return effects }
      state.current?.isIdle = true
      let holds = state.holds
      state.holds = [:]
      self.reconcile(&state, &effects)
      for (holdID, hold) in holds {
        let result = IndexingBackgroundResult(
          hasRemainingWork: hold.stats.hasDeferred,
          didChangeStore: hold.didChangeStore
        )
        self.finishHold(holdID, hold, with: HoldEnding(outcome: .finished(result), end: "idle"), &state, &effects)
      }
      return effects
    }
    effects.perform()
    self.log(effects.logs)
  }

  /// 실행 Task 가 끝났다. 멈춘 실행이면 정리만 하고, 스스로 끝난 실행이면 BG 가 쥔 것을 돌려보내고 활성이면 앞 구독자 스트림을 끝낸다
  /// (지금의 "멈춤" 의미). 비활성이면 앞 구독자를 그대로 두어 다시 활성이 될 때 새 실행으로 잇는다.
  /// 스스로 끝난 뒤 바로 다시 돌지 않게 새 실행을 시작하지 않는다(다음 `run()`·활성·`runInBackground` 가 시작한다).
  private func runEnded(_ id: UUID, _ end: IndexingRunEnd) {
    let effects = self.state.withLock { state -> Effects in
      var effects = Effects()
      state.stopping.removeAll { $0.id == id }
      guard state.current?.id == id else { return effects }
      state.current = nil
      let holds = state.holds
      state.holds = [:]
      for (holdID, hold) in holds {
        let result = IndexingBackgroundResult(
          hasRemainingWork: end.leavesRemainingWork || hold.stats.hasDeferred,
          didChangeStore: hold.didChangeStore
        )
        self.finishHold(holdID, hold, with: HoldEnding(outcome: .finished(result), end: end.rawValue), &state, &effects)
      }
      if state.isAppActive {
        effects.subscribersToFinish = Array(state.subscribers.values)
        state.subscribers = [:]
      }
      return effects
    }
    effects.perform()
    self.log(effects.logs)
  }

  private func record(_ event: BackgroundRunEvent) {
    self.state.withLock { state in
      for id in state.holds.keys {
        state.holds[id]?.stats.add(event)
      }
    }
  }

  private func didWrite() {
    self.state.withLock { state in
      for id in state.holds.keys {
        state.holds[id]?.didChangeStore = true
      }
    }
  }
}

// MARK: - 전이

extension IndexingExecutor {
  /// 도는 조건에 맞춰 실행을 시작하거나 멈춘다. 잠금 안에서 부른다.
  private func reconcile(_ state: inout State, _ effects: inout Effects, removingHold holdID: UUID? = nil) {
    if let holdID {
      state.holds[holdID] = nil
    }
    let shouldRun = (state.isAppActive && !state.subscribers.isEmpty) || !state.holds.isEmpty
    if shouldRun, state.current == nil {
      self.startRun(&state)
    } else if !shouldRun {
      self.stopCurrent(&state, &effects)
    }
  }

  /// 새 실행을 시작한다. Task 는 멈춘 실행들의 문이 손을 뗀 뒤에 `IndexingRun` 을 만든다.
  private func startRun(_ state: inout State) {
    let id = UUID()
    let gate = StoreGate(onWrite: { [weak self] in self?.didWrite() })
    let previousGates = state.stopping.map(\.gate)
    // 실행 Task 는 실행기를 붙잡는다(지금처럼 실행이 끝날 때까지 구독자에게 보낸다). 끝나면 `runEnded` 가 handle 을 놓아 순환이 풀린다.
    let environment = RunEnvironment(
      isBackground: { self.state.withLock { !$0.isAppActive } },
      shouldYield: {
        let checks = self.state.withLock { $0.holds.values.map(\.shouldYield) }
        return checks.contains { $0() }
      },
      onIdle: { self.runIdle(id) },
      record: { self.record($0) }
    )
    let task = Task(priority: .utility) { [makeRun] in
      for previous in previousGates {
        await previous.drained()
      }
      guard !Task.isCancelled else {
        self.runEnded(id, .cancelled)
        return
      }
      var run = makeRun(gate, environment)
      let end = await run.start { self.report(id, $0) }
      self.runEnded(id, end)
    }
    state.current = RunHandle(id: id, gate: gate, task: task)
  }

  /// 도는 실행을 멈춘다: 문을 닫고(그 뒤 새 저장소 호출 없음) Task 를 취소한다(잠금 밖에서).
  private func stopCurrent(_ state: inout State, _ effects: inout Effects) {
    guard let current = state.current else { return }
    state.current = nil
    current.gate.close()
    if let task = current.task {
      effects.tasksToCancel.append(task)
    }
    state.stopping.append(current)
  }

  /// hold 하나를 끝낸다. continuation 을 받기 전이면 결과를 두어 받을 때 바로 돌아오게 한다.
  private func finishHold(
    _ id: UUID,
    _ hold: Hold,
    with ending: HoldEnding,
    _ state: inout State,
    _ effects: inout Effects
  ) {
    state.holds[id] = nil
    if let continuation = hold.continuation {
      effects.holdsToResume.append((continuation, ending.outcome))
    } else {
      state.earlyHoldOutcomes[id] = ending.outcome
    }
    let elapsed = ContinuousClock.now - hold.startedAt
    effects.logs.append(HoldLog(
      stats: hold.stats,
      isAppActive: state.isAppActive,
      end: ending.end,
      seconds: Int(elapsed.components.seconds)
    ))
  }
}
