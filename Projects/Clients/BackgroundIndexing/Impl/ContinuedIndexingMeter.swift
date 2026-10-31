import BackgroundIndexingInterface
import IndexingInterface
import TripPlaceInterface

/// 계속 처리 작업의 시스템 진행 표시(`Progress` 단위·단계·수)를 진행률 차례에서 계산한다. 개수만 다룬다.
/// 단위: 분류 1장 = 1, 글자 읽기 1장 = 1, 장소 키 1개 = 1. 완료 수는 줄지 않고, 전체는 회차 끝에 그 회차의 못 한 키만큼 줄 때 말고는 줄지 않는다.
/// - 분류: 남은 수(전체 − 분류 − 건너뜀)가 줄어든 만큼만 더한다. 새 사진·재시작으로 남은 수가 늘어도 완료 수는 그대로다.
/// - 글자 읽기: 이번 실행 처리 수(읽음 + 건너뜀)가 는 만큼 더한다. 줄어든 값은 `runRestarted()` 뒤 처음 온 것만 새 실행으로 보고
///   (0 부터 센다) 나머지는 순서가 뒤바뀐 옛 값으로 버린다.
/// - 장소: `indexingEnded()` 뒤에는 분류 남은 수·글자 대기를 0 으로 본다(그 몫은 처리 작업이 잇는다). 회차의 처리한 키를 더한다.
struct ContinuedIndexingMeter {
  private(set) var completed: Int64 = 0
  private(set) var total: Int64 = 1
  /// 분류·글자 읽기가 끝났다는 진행률(`isFinished`)을 받았는지.
  private(set) var isFinished = false
  private var latest: IndexingProgress?
  private var classifiedDone = 0
  private var textDone = 0
  private var lastRemaining: Int?
  private var lastTextDone: Int?
  private var isRestartMarked = false
  private var hasIndexingEnded = false
  /// 끝난 회차들의 처리한 키 합.
  private var endedRoundsDone = 0
  /// 도는 회차(시작 뒤 끝 전)의 처리한 키·전체. 알림 전이면 0·0.
  private var round: TripPlacePrefetchProgress?

  /// 지금까지 끝난 회차 수(Debug 수치 로그).
  private(set) var endedRounds = 0

  /// 처리한 장소 키 합(Debug 수치 로그).
  var placeDone: Int {
    self.endedRoundsDone + (self.round?.doneCount ?? 0)
  }

  /// 시스템 진행 화면에 보일 단계와 수. 바꿀 것이 없으면(분류·글자 읽기를 마쳤고 회차가 돌지 않음) nil.
  var status: ContinuedIndexingStatus? {
    if self.hasIndexingEnded {
      guard let round else { return nil }
      return ContinuedIndexingStatus(
        stage: .fetchingPlaceNames,
        doneCount: round.doneCount,
        totalCount: round.totalCount
      )
    }
    guard let latest else { return nil }
    switch latest.phase {
    case .classifying:
      return ContinuedIndexingStatus(
        stage: .classifying,
        doneCount: latest.indexedCount + latest.skippedCount,
        totalCount: latest.totalCount
      )
    case .recognizingText:
      let done = latest.recognizedTextCount + latest.skippedTextCount
      return ContinuedIndexingStatus(
        stage: .recognizingText,
        doneCount: done,
        totalCount: done + latest.pendingTextCount
      )
    case .finished:
      return nil
    }
  }

  mutating func receive(_ progress: IndexingProgress) {
    guard !self.hasIndexingEnded else { return }
    let remaining = max(0, progress.totalCount - progress.indexedCount - progress.skippedCount)
    if let lastRemaining {
      self.classifiedDone += max(0, lastRemaining - remaining)
    }
    self.lastRemaining = remaining
    let textDone = progress.recognizedTextCount + progress.skippedTextCount
    if let lastTextDone, textDone < lastTextDone {
      if self.isRestartMarked {
        self.isRestartMarked = false
        self.textDone += textDone
        self.lastTextDone = textDone
      }
    } else {
      self.textDone += textDone - (self.lastTextDone ?? textDone)
      self.lastTextDone = textDone
    }
    self.latest = progress
    if progress.isFinished {
      self.isFinished = true
    }
    self.update()
  }

  /// 앱이 앞으로 와 실행기가 새 실행을 시작했다. 다음에 오는 글자 처리 수 감소를 새 실행으로 받는다.
  mutating func runRestarted() {
    self.isRestartMarked = true
  }

  /// 실행기 hold 를 놓았다. 그 뒤 분류 진행률은 버리고 남은 분류·글자 대기를 막대에 넣지 않는다.
  mutating func indexingEnded() {
    self.hasIndexingEnded = true
    self.update()
  }

  mutating func placeRoundStarted() {
    self.round = TripPlacePrefetchProgress(doneCount: 0, totalCount: 0)
    self.update()
  }

  mutating func placeProgress(_ progress: TripPlacePrefetchProgress) {
    let done = max(self.round?.doneCount ?? 0, progress.doneCount)
    self.round = TripPlacePrefetchProgress(doneCount: done, totalCount: max(progress.totalCount, done))
    self.update()
  }

  /// 회차가 돌아왔다. 처리한 키는 완료에 남기고 못 한 키는 전체에서 뺀다.
  mutating func placeRoundEnded() {
    guard let round else { return }
    self.round = nil
    self.endedRoundsDone += round.doneCount
    self.endedRounds += 1
    self.total = max(self.total - Int64(round.totalCount - round.doneCount), self.completed, 1)
    self.update()
  }

  private mutating func update() {
    var remaining = 0
    if !self.hasIndexingEnded, let latest {
      remaining = (self.lastRemaining ?? 0) + latest.pendingTextCount
    }
    if let round {
      remaining += round.totalCount - round.doneCount
    }
    self.completed = max(self.completed, Int64(self.classifiedDone + self.textDone + self.placeDone))
    self.total = max(self.total, self.completed + Int64(remaining), 1)
  }
}
