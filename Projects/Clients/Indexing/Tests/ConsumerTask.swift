import Synchronization

/// 분석 도중 Fake(분석·저장소·언어 모델)에서 끝낼 수 있는 구독 Task.
final class ConsumerTask: Sendable {
  private let task = Mutex<Task<Void, Never>?>(nil)

  func start(_ operation: @escaping @Sendable () async -> Void) {
    self.task.withLock { $0 = Task(operation: operation) }
  }

  func cancel() {
    self.task.withLock { $0?.cancel() }
  }

  func wait() async {
    await self.task.withLock { $0 }?.value
  }
}
