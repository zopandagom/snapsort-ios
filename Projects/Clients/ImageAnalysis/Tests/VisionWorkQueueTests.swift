import Dispatch
import Foundation
import Synchronization
import Testing
@testable import ImageAnalysisImpl

/// 세션 직렬 실행 도우미(`VisionWorkQueue`)의 차례·취소·대기 시간을 본다(시한·버린 큐는 `VisionWorkQueueTimeoutTests`).
/// 시한 타이머는 수동 스케줄러(`ManualTimer`)라 터뜨리지 않으면 터지지 않는다. Vision 요청은 perform 하지 않는다.
struct VisionWorkQueueTests {
  @Test("겹쳐 넣은 작업은 차례로 돈다")
  func runsSerially() async throws {
    let queue = VisionWorkQueue(label: "test.serial", schedule: ManualTimer().schedule)
    let counter = Mutex((running: 0, maximum: 0))
    let body: @Sendable () -> Int = {
      counter.withLock { state in
        state.running += 1
        state.maximum = max(state.maximum, state.running)
      }
      Thread.sleep(forTimeInterval: 0.02)
      counter.withLock { $0.running -= 1 }
      return 1
    }

    async let first = queue.run(timeout: .seconds(5), body)
    async let second = queue.run(timeout: .seconds(5), body)
    async let third = queue.run(timeout: .seconds(5), body)
    let results = try await [first, second, third]

    #expect(results == [1, 1, 1])
    #expect(counter.withLock { $0.maximum } == 1)
  }

  @Test("앞 작업을 기다리는 동안 취소하면 바로 취소를 던지고, 그 작업은 시작하지 않는다")
  func cancelWhileWaiting() async throws {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.waiting", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let calls = Mutex(0)

    let first = Task { try await queue.run(timeout: .seconds(5)) { blocker.wait(); return 1 } }
    _ = await timer.next()

    let second = Task { () async -> (any Error)? in
      do {
        _ = try await queue.run(timeout: .seconds(5)) { calls.withLock { $0 += 1 } }
        return nil
      } catch {
        return error
      }
    }
    second.cancel()

    #expect(await second.value is CancellationError)
    blocker.signal()
    #expect(try await first.value == 1)
    // 큐가 둘째 자리를 지난 뒤에 본다.
    _ = try await queue.run(timeout: .seconds(5)) { 0 }
    #expect(calls.withLock { $0 } == 0)
  }

  @Test("실행 중 취소하면 끝나기를 기다리지 않고 취소를 던지고, 작업은 끝까지 돈다")
  func cancelWhileRunning() async throws {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.running", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let ended = Mutex(false)

    let task = Task { () async -> (any Error)? in
      do {
        _ = try await queue.run(timeout: .seconds(5), hooks: VisionWorkQueue.Hooks(ended: { _ in
          ended.withLock { $0 = true }
        })) {
          blocker.wait()
          return 1
        }
        return nil
      } catch {
        return error
      }
    }
    _ = await timer.next()
    task.cancel()

    #expect(await task.value is CancellationError)
    #expect(!ended.withLock { $0 })
    blocker.signal()
    _ = try await queue.run(timeout: .seconds(5)) { 0 }
    #expect(ended.withLock { $0 })
  }

  @Test("큐를 기다린 시간은 시한에 들지 않는다: 줄 선 작업은 시작할 때 타이머를 건다")
  func waitingIsNotTimed() async throws {
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.waiting-time", schedule: timer.schedule)
    let blocker = DispatchSemaphore(value: 0)
    let (enqueues, enqueueSignal) = AsyncStream.makeStream(of: Void.self)

    let first = Task { try await queue.run(timeout: .seconds(5)) { blocker.wait(); return 1 } }
    _ = await timer.next()
    let second = Task {
      try await queue.run(timeout: .seconds(5), hooks: VisionWorkQueue.Hooks(enqueued: { enqueueSignal.yield() })) { 2 }
    }
    var enqueueIterator = enqueues.makeAsyncIterator()
    await enqueueIterator.next()

    #expect(timer.count == 1)
    blocker.signal()
    #expect(try await first.value == 1)
    _ = await timer.next()
    #expect(try await second.value == 2)
    #expect(timer.count == 2)
  }

  @Test("body 가 던진 오류는 그대로 던지고, 이미 취소된 Task 에서 부르면 시작하지 않고 취소를 던진다")
  func rethrowsAndSkipsCancelled() async throws {
    struct BodyError: Error {}
    let timer = ManualTimer()
    let queue = VisionWorkQueue(label: "test.errors", schedule: timer.schedule)
    let calls = Mutex(0)

    await #expect(throws: BodyError.self) {
      try await queue.run(timeout: .seconds(5)) { () throws -> Int in throw BodyError() }
    }
    let cancelled = Task { () async -> (any Error)? in
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try await queue.run(timeout: .seconds(5)) { calls.withLock { $0 += 1 } }
        return nil
      } catch {
        return error
      }
    }

    #expect(await cancelled.value is CancellationError)
    // 큐가 취소된 호출 자리를 지난 뒤에 본다.
    _ = try await queue.run(timeout: .seconds(5)) { 0 }
    #expect(calls.withLock { $0 } == 0)
    #expect(timer.count == 2)
  }
}
