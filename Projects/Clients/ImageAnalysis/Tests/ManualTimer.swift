import Synchronization
@testable import ImageAnalysisImpl

/// `VisionWorkQueue.run` 의 결과.
enum WorkOutcome: Equatable {
  case success(Int)
  case failure(VisionWorkQueue.Failure)
  case cancelled
  case other

  /// `run` 의 결과를 비교할 수 있게 바꾼다.
  static func of(_ run: () async throws -> Int) async -> WorkOutcome {
    do {
      return try await .success(run())
    } catch let failure as VisionWorkQueue.Failure {
      return .failure(failure)
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .other
    }
  }
}

/// 받은 시한 타이머를 쥐었다가 테스트가 직접 터뜨리게 하는 스케줄러. 건 순서대로 `next()` 로 받는다(한 번에 한 곳에서 기다린다).
final class ManualTimer: Sendable {
  /// 걸린 타이머 하나.
  struct Scheduled: Sendable {
    let delay: Duration
    let fire: @Sendable () -> Void
  }

  private struct State {
    var pending: [Scheduled] = []
    var waiter: CheckedContinuation<Scheduled, Never>?
    var count = 0
  }

  private let state = Mutex(State())

  var schedule: VisionWorkQueue.Schedule {
    { delay, fire in
      let scheduled = Scheduled(delay: delay, fire: fire)
      let waiter = self.state.withLock { state -> CheckedContinuation<Scheduled, Never>? in
        state.count += 1
        guard let waiter = state.waiter else {
          state.pending.append(scheduled)
          return nil
        }
        state.waiter = nil
        return waiter
      }
      waiter?.resume(returning: scheduled)
    }
  }

  /// 지금까지 건 타이머 수.
  var count: Int {
    self.state.withLock(\.count)
  }

  /// 다음에 건 타이머. 아직 없으면 걸릴 때까지 기다린다.
  func next() async -> Scheduled {
    await withCheckedContinuation { continuation in
      let ready = self.state.withLock { state -> Scheduled? in
        guard state.pending.isEmpty else {
          return state.pending.removeFirst()
        }
        state.waiter = continuation
        return nil
      }
      if let ready {
        continuation.resume(returning: ready)
      }
    }
  }
}
