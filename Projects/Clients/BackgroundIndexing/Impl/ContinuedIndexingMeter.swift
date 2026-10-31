import BackgroundIndexingInterface
import IndexingInterface
import TripPlaceInterface

/// 계속 처리 작업의 시스템 진행 표시(`Progress` 단위·단계·수)를 진행률 차례에서 계산한다. 개수만 다룬다.
/// 단위는 추정 시간 가중이다(`Weights`, 단위 1 ≈ 10ms): 시스템은 단위 진행 속도가 처음 몇 분의 기준에서 크게 벗어나면 정지로 보고 작업을 끝낸다.
/// 그래서 단계가 바뀌어도 속도가 꺾이지 않게 아직 분류하지 않은 장에 앞으로 생길 글자 읽기 몫(글자 비율 추정)을, 회차가 돌 수 있으면
/// 회차 키 상한만큼의 장소 몫을 처음부터 전체에 넣는다. 완료 수는 줄지 않고, 전체는 완료 + 남은 추정이라 추정을 따라 오르내린다(완료 아래로는 안 감).
/// 단계·수(`status`)는 실제 장·키 개수다.
/// - 분류: 남은 수(전체 − 분류 − 건너뜀)가 줄어든 만큼만 더한다. 새 사진·재시작으로 남은 수가 늘어도 완료 수는 그대로다.
/// - 글자 읽기: 이번 실행 처리 수(읽음 + 건너뜀)가 는 만큼 더한다. 줄어든 값은 `runRestarted()` 뒤 처음 온 것만 새 실행으로 보고
///   (0 부터 센다) 나머지는 순서가 뒤바뀐 옛 값으로 버린다.
/// - 글자 비율: 이번 작업에서 늘어난 글자 대기 합 ÷ 분류한 장 수를 사전값과 섞는다. 남은 분류 몫에만 쓴다.
/// - 장소: `indexingEnded()` 뒤에는 분류 남은 수·글자 대기를 0 으로 본다(그 몫은 처리 작업이 잇는다). 회차의 처리한 키를 더한다.
///   회차가 키 수를 알리면 예약을 그 회차의 남은 키로 바꾼다(키 수 ≤ 예약이라 전체가 늘지 않음).
struct ContinuedIndexingMeter {
  /// 단위 무게. 실측(실기기 iPhone 14 Pro, 계속 처리 뒤)에 근거한 임시 값이다.
  struct Weights: Equatable {
    /// 분류 1장(썸네일·분류·바코드 확인·특징 벡터·저장 포함). 실측 평균 약 0.16초/장.
    var classify: Int64
    /// 글자 읽기 1장(원본 읽기·OCR·규칙·모델 보강·저장). 실측 약 2초/장(모델 보강 없는 기기).
    var text: Int64
    /// 장소 키 1개. 요청 간격 3초 + 응답 0.5초 가정(실측 없음).
    var placeKey: Int64
    /// 글자 비율 사전값(분류한 장 중 글자 대기가 되는 비율). 과소 추정이면 전체가 늘어 속도가 떨어지므로 넉넉하게 잡는다.
    var textShare: Double
    /// 사전값의 무게(장 수). 이번 작업에서 이만큼 분류하면 관찰값과 사전값이 반씩 섞인다.
    var textSharePrior: Int
    /// 회차가 돌 수 있을 때 미리 넣는 장소 키 수. TripPlace Impl 의 `TripPlacePolicy.roundLimit`(회차 키 상한)과 맞춘다
    /// (Impl 끼리 import 할 수 없어 상수). 바꾸면 둘을 함께 바꾼다.
    var placeReserveKeys: Int

    static let `default` = Weights(
      classify: 16,
      text: 200,
      placeKey: 350,
      textShare: 0.2,
      textSharePrior: 100,
      placeReserveKeys: 30
    )
  }

  let weights: Weights
  private(set) var completed: Int64 = 0
  private(set) var total: Int64 = 1
  /// 분류·글자 읽기가 끝났다는 진행률(`isFinished`)을 받았는지.
  private(set) var isFinished = false
  private var latest: IndexingProgress?
  /// 이번 작업에서 분류(또는 건너뜀)한 장 수.
  private(set) var classifiedCount = 0
  /// 이번 작업에서 글자 읽기(또는 건너뜀)한 장 수.
  private(set) var textCount = 0
  /// 이번 작업에서 늘어난 글자 대기 합.
  private var discoveredText = 0
  private var lastRemaining: Int?
  private var lastTextDone: Int?
  private var lastPending: Int?
  private var isRestartMarked = false
  private var hasIndexingEnded = false
  /// 끝난 회차들의 처리한 키 합.
  private var endedRoundsDone = 0
  /// 도는 회차(시작 뒤 끝 전)의 처리한 키·전체. 알림 전이면 0·0.
  private var round: TripPlacePrefetchProgress?
  /// 도는 회차가 키 수를 알렸는지.
  private var hasRoundReported = false
  /// 아직 키 수를 모르는 회차 몫으로 넣어 둔 키 수.
  private var placeReserve: Int

  /// 지금까지 끝난 회차 수(Debug 수치 로그).
  private(set) var endedRounds = 0

  /// - Parameters:
  ///   - weights: 단위 무게.
  ///   - reservesPlaceRound: 미리 받기 회차가 돌 수 있다. 참이면 처음부터 회차 키 상한만큼 장소 몫을 넣는다.
  init(weights: Weights = .default, reservesPlaceRound: Bool = false) {
    self.weights = weights
    self.placeReserve = reservesPlaceRound ? weights.placeReserveKeys : 0
  }

  /// 처리한 장소 키 합(Debug 수치 로그).
  var placeDone: Int {
    self.endedRoundsDone + (self.round?.doneCount ?? 0)
  }

  /// 글자 비율 추정: (늘어난 글자 대기 + 사전값 × 사전 무게) ÷ (분류한 장 + 사전 무게), 1 이하.
  var textShare: Double {
    let prior = Double(self.weights.textSharePrior)
    let share = (Double(self.discoveredText) + self.weights.textShare * prior) / (Double(self.classifiedCount) + prior)
    return min(1, share)
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
      self.classifiedCount += max(0, lastRemaining - remaining)
    }
    self.lastRemaining = remaining
    let textDone = progress.recognizedTextCount + progress.skippedTextCount
    if let lastTextDone, textDone < lastTextDone {
      if self.isRestartMarked {
        self.isRestartMarked = false
        self.textCount += textDone
        self.lastTextDone = textDone
      }
    } else {
      self.textCount += textDone - (self.lastTextDone ?? textDone)
      self.lastTextDone = textDone
    }
    // 첫 값은 기준만 잡는다.
    if let lastPending, progress.pendingTextCount > lastPending {
      self.discoveredText += progress.pendingTextCount - lastPending
    }
    self.lastPending = progress.pendingTextCount
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
  /// 장소 예약은 그대로 둔다(알리지 않은 회차 1 뒤에 회차 2 가 올 수 있다).
  mutating func indexingEnded() {
    self.hasIndexingEnded = true
    self.update()
  }

  mutating func placeRoundStarted() {
    self.round = TripPlacePrefetchProgress(doneCount: 0, totalCount: 0)
    self.hasRoundReported = false
    self.update()
  }

  /// 회차의 첫 알림에서 예약을 그 회차의 키 수로 바꾼다.
  mutating func placeProgress(_ progress: TripPlacePrefetchProgress) {
    let done = max(self.round?.doneCount ?? 0, progress.doneCount)
    self.round = TripPlacePrefetchProgress(doneCount: done, totalCount: max(progress.totalCount, done))
    self.hasRoundReported = true
    self.placeReserve = 0
    self.update()
  }

  /// 회차가 돌아왔다. 처리한 키는 완료에 남고 못 한 키는 남은 추정에서 빠진다. 알리지 않고 끝난 회차는 hold 를 놓은 뒤면
  /// 예약도 뺀다(그 뒤 열릴 회차가 없다). hold 를 놓기 전이면 회차 2 가 올 수 있어 그대로 둔다.
  mutating func placeRoundEnded() {
    guard let round else { return }
    self.round = nil
    self.endedRoundsDone += round.doneCount
    self.endedRounds += 1
    if !self.hasRoundReported, self.hasIndexingEnded {
      self.placeReserve = 0
    }
    self.update()
  }

  private mutating func update() {
    let weights = self.weights
    var remaining: Int64 = 0
    if !self.hasIndexingEnded, let latest {
      let unclassified = self.lastRemaining ?? 0
      let textReserve = (Double(unclassified) * self.textShare * Double(weights.text)).rounded()
      remaining += Int64(unclassified) * weights.classify + Int64(textReserve)
      remaining += Int64(latest.pendingTextCount) * weights.text
    }
    if let round {
      remaining += Int64(round.totalCount - round.doneCount) * weights.placeKey
    }
    remaining += Int64(self.placeReserve) * weights.placeKey
    let done = Int64(self.classifiedCount) * weights.classify + Int64(self.textCount) * weights.text
      + Int64(self.placeDone) * weights.placeKey
    self.completed = max(self.completed, done)
    self.total = max(self.completed + remaining, 1)
  }
}
