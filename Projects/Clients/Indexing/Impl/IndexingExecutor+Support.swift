import Foundation
import IndexingInterface
#if DEBUG
  import os
#endif

// 공유 실행기(`IndexingExecutor`)의 상태 타입과 Debug 수치 로그.
extension IndexingExecutor {
  struct State {
    var subscribers: [UUID: AsyncStream<IndexingProgress>.Continuation] = [:]
    var isAppActive = true
    var holds: [UUID: Hold] = [:]
    /// continuation 을 받기 전에 끝난 hold 의 결과.
    var earlyHoldOutcomes: [UUID: HoldOutcome] = [:]
    var current: RunHandle?
    /// 멈추라 했고 아직 Task 가 끝나지 않은 실행(문은 닫혔다).
    var stopping: [RunHandle] = []
    /// 비활성 동안 받은 최신 진행률.
    var heldProgress: IndexingProgress?
  }

  /// 도는(또는 멈추는 중인) 실행 하나.
  struct RunHandle {
    let id: UUID
    let gate: StoreGate
    var task: Task<Void, Never>?
    var latest: IndexingProgress?
    /// 변경을 기다리는 중(할 일이 없다).
    var isIdle = false
  }

  /// `runInBackground` 호출 하나.
  struct Hold {
    var continuation: CheckedContinuation<HoldOutcome, Never>?
    let shouldYield: @Sendable () -> Bool
    let progress: @Sendable (IndexingProgress) -> Void
    var didChangeStore = false
    var stats = BackgroundRunStats()
    let startedAt = ContinuousClock.now
  }

  enum HoldOutcome: Sendable {
    case finished(IndexingBackgroundResult)
    /// 부른 Task 가 취소됐다. 멈춘 실행의 문이 있으면 손을 뗄 때까지 기다린 뒤 돌아온다.
    case cancelled(gate: StoreGate?, didChangeStore: Bool)
  }

  /// hold 하나를 끝낼 때의 결과와 Debug 수치 로그에 남길 끝 이유.
  struct HoldEnding {
    let outcome: HoldOutcome
    let end: String
  }

  /// 잠금 안에서 정하고 잠금 밖에서 하는 일.
  struct Effects {
    var tasksToCancel: [Task<Void, Never>] = []
    var holdsToResume: [(CheckedContinuation<HoldOutcome, Never>, HoldOutcome)] = []
    var progressToSubscribers: (IndexingProgress, [AsyncStream<IndexingProgress>.Continuation])?
    var progressToHolds: (IndexingProgress, [@Sendable (IndexingProgress) -> Void])?
    var subscribersToFinish: [AsyncStream<IndexingProgress>.Continuation] = []
    var logs: [HoldLog] = []

    func perform() {
      self.tasksToCancel.forEach { $0.cancel() }
      if let toSubscribers = self.progressToSubscribers {
        toSubscribers.1.forEach { $0.yield(toSubscribers.0) }
      }
      if let toHolds = self.progressToHolds {
        toHolds.1.forEach { $0(toHolds.0) }
      }
      self.subscribersToFinish.forEach { $0.finish() }
      self.holdsToResume.forEach { $0.0.resume(returning: $0.1) }
    }
  }

  /// hold 가 끝날 때의 Debug 수치 로그 재료.
  struct HoldLog {
    let stats: BackgroundRunStats
    let isAppActive: Bool
    let end: String
    let seconds: Int
  }

  // MARK: - Debug 수치 로그

  /// BG 가 쥔 동안의 수를 남긴다(docs/CONVENTIONS.md §4). 정수·고정 문자열만이고 식별자·텍스트·좌표는 없다. Release 에서는 아무것도 하지 않는다.
  func log(_ logs: [HoldLog]) {
    #if DEBUG
      guard !logs.isEmpty else { return }
      let isFeaturePrintAvailable = self.isFeaturePrintAvailable() ? 1 : 0
      for log in logs {
        let stats = log.stats
        Self.logger.notice(
          """
          indexing hold ended classified=\(stats.classified, privacy: .public) \
          recognized=\(stats.recognized, privacy: .public) \
          barcodeDeferred=\(stats.barcodeDeferred, privacy: .public) \
          modelDeferred=\(stats.modelDeferred, privacy: .public) \
          modelRejected=\(stats.modelRejected, privacy: .public) \
          visionFailures=\(stats.visionFailures, privacy: .public) \
          featurePrints=\(stats.featurePrints, privacy: .public) \
          featurePrintFailures=\(stats.featurePrintFailures, privacy: .public) \
          featurePrintAvailable=\(isFeaturePrintAvailable, privacy: .public) \
          classificationHeld=\(stats.classificationHeld, privacy: .public) \
          active=\(log.isAppActive ? 1 : 0, privacy: .public) \
          seconds=\(log.seconds, privacy: .public) end=\(log.end, privacy: .public)
          """
        )
      }
    #endif
  }

  #if DEBUG
    static let logger = Logger(subsystem: "com.zopandagom.snapsort", category: "BackgroundIndexing")
  #endif
}
