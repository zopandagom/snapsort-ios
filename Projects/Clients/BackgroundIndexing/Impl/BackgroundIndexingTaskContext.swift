import BackgroundIndexingInterface
import IndexingInterface
import TripPlaceInterface

extension BackgroundIndexingClientImpl {
  /// 조정자가 쥔 작업의 종류.
  enum TaskKind {
    /// 시스템이 충전 중에 실행하는 처리 작업(`BGProcessingTask`).
    case processing
    /// 사용자가 앞에서 시작한 계속 처리 작업(`BGContinuedProcessingTask`).
    case continued
  }

  /// 계속 처리 작업의 사용자에게 보이는 단계. `.pending` 은 제출 성공 ~ 핸들러 도착, `.finishing` 은 실행 끝 ~ 완료 알림.
  enum ContinuedPhase {
    case idle
    case pending
    case running
    case finishing
  }

  /// 계속 처리 작업 실행 중 조정자에게 오는 신호(진행 표시용). 개수만 담는다.
  enum ContinuedSignal: Sendable {
    case indexing(IndexingProgress)
    case placeRoundStarted
    case placeProgress(TripPlacePrefetchProgress)
    case placeRoundEnded
  }

  /// 처리 중인 작업 하나.
  final class TaskContext {
    let task: any BackgroundProcessingTask
    let kind: TaskKind
    /// 계속 처리 작업의 진행 표시. 처리 작업이면 nil.
    let display: (any ContinuedProcessingTask)?
    /// 계속 처리 작업의 문구. 처리 작업이면 nil.
    let text: ContinuedIndexingText?
    /// 분류 hold 와 미리 받기 회차를 함께 쥔 실행. 취소하면 둘 다 멈춘다.
    var work: Task<IndexingBackgroundResult, Never>?
    /// 분류 hold 만 쥔 실행. 취소하면 hold 만 놓고 회차는 그대로 간다.
    var indexingWork: Task<IndexingBackgroundResult, Never>?
    /// 계속 처리 작업의 신호 소비. 실행이 끝나면 신호 스트림이 닫혀 끝난다. `finish` 가 이것을 기다려 마지막 진행률까지 반영한다.
    var signalWork: Task<Void, Never>?
    var isExpired = false
    var isCompleted = false
    /// 계속 처리 작업이 분류·글자 읽기 끝(`IndexingProgress.isFinished`)을 받았는지.
    var reachedFinished = false
    var meter = ContinuedIndexingMeter()
    /// 마지막으로 보인 제목·부제.
    var shownTitle: String?
    var shownSubtitle: String?
    #if DEBUG
      let startedAt = ContinuousClock.now
      var lastSignalAt = ContinuousClock.now
      var maxGap: Duration = .zero
      var finishedAt: ContinuousClock.Instant?
    #endif

    init(task: any BackgroundProcessingTask) {
      self.task = task
      self.kind = .processing
      self.display = nil
      self.text = nil
    }

    init(continued task: any ContinuedProcessingTask, text: ContinuedIndexingText) {
      self.task = task
      self.kind = .continued
      self.display = task
      self.text = text
    }

    /// 완료는 한 번만 알린다.
    func complete(success: Bool) {
      guard !self.isCompleted else { return }
      self.isCompleted = true
      self.task.setTaskCompleted(success: success)
    }
  }
}
