import Dispatch
import Foundation
import Synchronization
import Testing
@testable import ImageAnalysisImpl

/// 세션 직렬 실행 도우미(`VisionWorkQueue`)의 시한과 버린 큐를 본다. 시한 타이머는 수동 스케줄러(`ManualTimer`)라
/// 테스트가 직접 터뜨린다(실제 시간을 기다리지 않는다). 작업은 세마포어로 막아 둔다. Vision 요청은 perform 하지 않는다.
struct VisionWorkQueueTimeoutTests {
  @Test("시한을 넘기면 부른 쪽은 바로 시한 초과로 돌아오고 큐를 버리며, 늦게 돌아온 작업은 시한 뒤로 알리고 결과는 버린다")
  func timesOut() async {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.timeout", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let timeouts = Mutex<[VisionWorkQueue.TimeoutInfo]>([])
    let (ends, endSignal) = AsyncStream.makeStream(of: Bool.self)
    let hooks = VisionWorkQueue.Hooks(
      ended: { endSignal.yield($0) },
      timedOut: { info in timeouts.withLock { $0.append(info) } }
    )

    let task = Task {
      await WorkOutcome.of { try await queue.run(timeout: .seconds(5), hooks: hooks) { blocker.wait(); return 1 } }
    }
    let scheduled = await timer.next()
    scheduled.fire()

    #expect(await task.value == .failure(.timedOut))
    #expect(timeouts.withLock { $0 } == [VisionWorkQueue.TimeoutInfo(isCallerWaiting: true, releasedWaiting: 0)])
    #expect(queue.isAbandoned)
    blocker.signal()
    var endIterator = ends.makeAsyncIterator()
    #expect(await endIterator.next() == true)
  }

  @Test("시한 안에 끝난 뒤 타이머가 터지면 아무 일도 없고 큐는 그대로 쓴다")
  func timerAfterCompletionIsIgnored() async throws {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.in-time", schedule: timer.schedule)
    let timeouts = Mutex(0)
    let ended = Mutex<[Bool]>([])
    let hooks = VisionWorkQueue.Hooks(
      ended: { afterTimeout in ended.withLock { $0.append(afterTimeout) } },
      timedOut: { _ in timeouts.withLock { $0 += 1 } }
    )

    #expect(try await queue.run(timeout: .seconds(5), hooks: hooks) { 1 } == 1)
    let scheduled = await timer.next()
    scheduled.fire()

    #expect(ended.withLock { $0 } == [false])
    #expect(timeouts.withLock { $0 } == 0)
    #expect(!queue.isAbandoned)
    #expect(try await queue.run(timeout: .seconds(5)) { 2 } == 2)
  }

  @Test("시한이 터지면 줄 선 호출은 바로 버린 큐로 풀리고 그 작업은 돌지 않는다")
  func releasesWaitingOnTimeout() async {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.release", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let timeouts = Mutex<[VisionWorkQueue.TimeoutInfo]>([])
    let calls = Mutex(0)
    let (enqueues, enqueueSignal) = AsyncStream.makeStream(of: Void.self)
    let (ends, endSignal) = AsyncStream.makeStream(of: Bool.self)

    let first = Task {
      await WorkOutcome.of {
        try await queue.run(timeout: .seconds(5), hooks: VisionWorkQueue.Hooks(
          ended: { endSignal.yield($0) },
          timedOut: { info in timeouts.withLock { $0.append(info) } }
        )) {
          blocker.wait()
          return 1
        }
      }
    }
    let scheduled = await timer.next()
    let waiting = (0 ..< 2).map { _ in
      Task {
        await WorkOutcome.of {
          try await queue.run(timeout: .seconds(5), hooks: VisionWorkQueue.Hooks(enqueued: { enqueueSignal.yield() })) {
            calls.withLock { $0 += 1 }
            return 2
          }
        }
      }
    }
    var enqueueIterator = enqueues.makeAsyncIterator()
    await enqueueIterator.next()
    await enqueueIterator.next()
    scheduled.fire()

    #expect(await first.value == .failure(.timedOut))
    for task in waiting {
      #expect(await task.value == .failure(.abandoned))
    }
    #expect(timeouts.withLock { $0 } == [VisionWorkQueue.TimeoutInfo(isCallerWaiting: true, releasedWaiting: 2)])
    blocker.signal()
    var endIterator = ends.makeAsyncIterator()
    #expect(await endIterator.next() == true)
    // 버린 큐는 시작할 때 버림을 확인하므로 줄 선 작업은 차례가 와도 돌지 않는다.
    #expect(calls.withLock { $0 } == 0)
    #expect(timer.count == 1)
  }

  @Test("버린 큐에 새로 넣은 호출은 줄 서지 않고 바로 버린 큐로 돌아오며 타이머를 걸지 않는다")
  func newRunOnAbandonedQueue() async {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.abandoned", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let first = Task { await WorkOutcome.of { try await queue.run(timeout: .seconds(5)) { blocker.wait(); return 1 } } }
    await timer.next().fire()
    #expect(await first.value == .failure(.timedOut))
    let calls = Mutex(0)
    let enqueued = Mutex(false)

    let result = await WorkOutcome.of {
      try await queue.run(
        timeout: .seconds(5),
        hooks: VisionWorkQueue.Hooks(enqueued: { enqueued.withLock { $0 = true } })
      ) {
        calls.withLock { $0 += 1 }
        return 2
      }
    }

    #expect(result == .failure(.abandoned))
    #expect(calls.withLock { $0 } == 0)
    #expect(!enqueued.withLock { $0 })
    #expect(timer.count == 1)
    blocker.signal()
  }

  @Test("부른 쪽이 취소로 먼저 돌아가도 큐가 쥔 타이머는 터지고, 그때 부른 쪽이 기다리지 않았다고 알린다")
  func timesOutAfterCallerCancelled() async {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.cancel-timeout", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let timeouts = Mutex<[VisionWorkQueue.TimeoutInfo]>([])
    let hooks = VisionWorkQueue.Hooks(timedOut: { info in timeouts.withLock { $0.append(info) } })

    let task = Task {
      await WorkOutcome.of { try await queue.run(timeout: .seconds(5), hooks: hooks) { blocker.wait(); return 1 } }
    }
    let scheduled = await timer.next()
    task.cancel()
    #expect(await task.value == .cancelled)
    scheduled.fire()

    #expect(timeouts.withLock { $0 } == [VisionWorkQueue.TimeoutInfo(isCallerWaiting: false, releasedWaiting: 0)])
    #expect(queue.isAbandoned)
    blocker.signal()
  }

  @Test("시한 훅은 줄 선 호출을 풀기 전에 불린다(먼저 세대를 버리고 나중에 푼다)")
  func timeoutHookRunsBeforeRelease() async {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.order", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let hookCalled = Mutex(false)
    let (enqueues, enqueueSignal) = AsyncStream.makeStream(of: Void.self)

    let first = Task {
      await WorkOutcome.of {
        try await queue.run(
          timeout: .seconds(5),
          hooks: VisionWorkQueue.Hooks(timedOut: { _ in hookCalled.withLock { $0 = true } })
        ) {
          blocker.wait()
          return 1
        }
      }
    }
    let scheduled = await timer.next()
    let second = Task { () async -> (WorkOutcome, Bool) in
      let outcome = await WorkOutcome.of {
        try await queue
          .run(timeout: .seconds(5), hooks: VisionWorkQueue.Hooks(enqueued: { enqueueSignal.yield() })) { 2 }
      }
      return (outcome, hookCalled.withLock { $0 })
    }
    var enqueueIterator = enqueues.makeAsyncIterator()
    await enqueueIterator.next()
    scheduled.fire()

    let (outcome, hookCalledBeforeRelease) = await second.value
    #expect(outcome == .failure(.abandoned))
    #expect(hookCalledBeforeRelease)
    #expect(await first.value == .failure(.timedOut))
    blocker.signal()
  }

  @Test("시한은 호출마다 받은 값으로 걸고, 세대의 첫 작업은 적재를 덮는 긴 시한이다")
  func schedulesGivenTimeout() async throws {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.duration", schedule: timer.schedule)

    _ = try await queue.run(timeout: .seconds(7)) { 0 }
    _ = try await queue.run(timeout: .seconds(3)) { 0 }

    #expect(await timer.next().delay == .seconds(7))
    #expect(await timer.next().delay == .seconds(3))
    let session = VisionSession()
    let first = VisionSessions.Lease(kind: .classify, generation: 1, session: session, isFirstUse: true)
    let warmed = VisionSessions.Lease(kind: .classify, generation: 1, session: session, isFirstUse: false)
    #expect(first.timeout == VisionSession.firstUseTimeout)
    #expect(warmed.timeout == VisionSession.timeout)
    #expect(VisionSession.firstUseTimeout > VisionSession.timeout)
  }
}
