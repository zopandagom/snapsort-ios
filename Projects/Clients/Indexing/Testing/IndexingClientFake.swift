import IndexingInterface
import Synchronization

/// 테스트와 Example 앱용 대역. `run()` 마다 정해 둔 진행률을 차례로 보낸다.
/// 실제처럼 구독을 끝낼 때까지 이어지게 할 수 있고, 지금 돌고 있는 `run()` 수를 센다.
/// 구독이 끝났는지 호출 사이에 기록해야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class IndexingClientFake: IndexingClient {
  public let progress: [IndexingProgress]
  private let finishesAfterProgress: Bool
  private let runningCount = Mutex(0)

  /// - Parameter finishesAfterProgress: 참이면 진행률을 다 보낸 뒤 스트림을 끝낸다.
  ///   거짓이면 실제처럼 받는 쪽이 구독을 끝낼 때(Task 취소)까지 이어진다.
  public init(progress: [IndexingProgress] = [], finishesAfterProgress: Bool = true) {
    self.progress = progress
    self.finishesAfterProgress = finishesAfterProgress
  }

  /// 아직 끝나지 않은 `run()` 스트림 수.
  public var activeRunCount: Int {
    self.runningCount.withLock { $0 }
  }

  public func run() -> AsyncStream<IndexingProgress> {
    let (stream, continuation) = AsyncStream.makeStream(of: IndexingProgress.self)
    self.runningCount.withLock { $0 += 1 }
    continuation.onTermination = { [weak self] _ in
      self?.runningCount.withLock { $0 -= 1 }
    }
    for progress in self.progress {
      continuation.yield(progress)
    }
    if self.finishesAfterProgress {
      continuation.finish()
    }
    return stream
  }
}
