import IndexingInterface
import Synchronization

/// 테스트와 Example 앱용 대역. `run()` 마다 정해 둔 진행률을 차례로 보낸다.
/// 실제처럼 구독을 끝낼 때까지 이어지게 할 수 있고, 그동안 진행률을 더 보내거나 스트림을 끝내 인덱싱이 멈춘 것을 흉내 낼 수 있다.
/// 지금 돌고 있는 `run()` 과 지금까지 부른 `run()` 을 센다.
/// 구독이 끝났는지 호출 사이에 기록해야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class IndexingClientFake: IndexingClient {
  public let progress: [IndexingProgress]
  private let finishesAfterProgress: Bool
  private let state = Mutex(State())

  private struct State {
    var runCount = 0
    var runs: [Int: AsyncStream<IndexingProgress>.Continuation] = [:]
  }

  /// - Parameter finishesAfterProgress: 참이면 진행률을 다 보낸 뒤 스트림을 끝낸다.
  ///   거짓이면 실제처럼 받는 쪽이 구독을 끝낼 때(Task 취소)나 `finishRuns()` 까지 이어진다.
  public init(progress: [IndexingProgress] = [], finishesAfterProgress: Bool = true) {
    self.progress = progress
    self.finishesAfterProgress = finishesAfterProgress
  }

  /// 아직 끝나지 않은 `run()` 스트림 수.
  public var activeRunCount: Int {
    self.state.withLock { $0.runs.count }
  }

  /// 지금까지 `run()` 을 부른 횟수. 멈춘 인덱싱을 다시 시작했는지 확인하는 데 쓴다.
  public var runCount: Int {
    self.state.withLock { $0.runCount }
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

  /// `finish()` 가 `onTermination` 을 불러 잠금을 다시 잡으므로, 잠금 밖에서 보내도록 복사해 둔다.
  private func activeRuns() -> [AsyncStream<IndexingProgress>.Continuation] {
    self.state.withLock { Array($0.runs.values) }
  }
}
