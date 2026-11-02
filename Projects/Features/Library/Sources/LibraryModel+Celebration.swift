import IndexingInterface
import Observation

/// 분류 완료 축하 한 번. 보관함 화면이 "분류 완료" 카드를 잠깐 보이고 반짝이·햅틱을 한 번 낸다.
/// `id` 는 화면 진입 한 번(세대) 안에서 오르는 번호로, 햅틱·애니메이션 트리거로 쓴다. 숫자는 보이지 않는다
/// (끝낸 수는 1단계와 2단계를 더해 같은 사진을 두 번 셀 수 있다).
public struct IndexingCelebration: Sendable, Equatable {
  public let id: Int
}

extension LibraryModel {
  /// 축하할 만큼 큰 일의 기준(장). 화면 진입 뒤 첫 진행률의 남은 일과 이번 세대에서 실제로 끝낸 수가 모두 이 값 이상이어야 축하한다.
  /// 임시 값이다(docs/ARCHITECTURE.md §4 인덱싱).
  static let celebrationMinimumWork = 30
  /// 축하 카드가 머무는 시간. 지나면 카드가 접힌다. 언제 상태가 바뀌는지(Model 동작)라 DesignSystem 이 아니라 여기 둔다.
  /// 화면 애니메이션 시간은 DesignSystem 기준값을 쓴다.
  static let celebrationDwell: Duration = .milliseconds(2500)
}

/// 분류 완료 축하의 상태 기계(docs/ARCHITECTURE.md §4 인덱싱). `LibraryModel` 이 소유한다. 이 파일로 나눈 것은 LibraryModel 파일 길이 때문이다.
///
/// - 세대: 화면 진입(`onAppear()`) 한 번이 `begin()` 한 번이다. 세대 첫 진행률이 기준이 된다.
/// - 무장: 첫 진행률이 다 함이 아니고 남은 일(1단계 남은 수 + 2단계 대기 수)이 기준 이상이면 무장한다.
/// - 축하: 무장한 뒤 처음 온 다 함 진행률에서 무장을 풀고, 이번 세대에서 실제로 끝낸 수도 기준 이상이면 축하한다
///   (iCloud 에만 있어 미룬 장만 남은 실행의 헛축하를 막는다). 세대당 한 번이다.
/// - 앱이 뒤에 있으면 축하를 미뤘다가 앞으로 올 때(`sceneBecameActive()`) 보이고, 머무는 시간은 그때부터 잰다.
/// - 새 일이 있는 끝나지 않은 진행률(보관함 수가 축하 때보다 늘었거나 남은 일이 축하 때 미룬 수(1·2단계)보다 많음)이나 멈춤이 오면
///   보이던·미룬 축하를 버린다(진행 카드·멈춤 카드가 이긴다). 축하는 무장을 푼 뒤에 만들므로, 버린 축하는 이번 세대에서 다시 나오지 않는다
///   (세대당 한 번). 축하를 만들기 전 무장한 채 멈췄으면 다시 시도로 끝까지 갈 때 축하한다.
/// - 인덱서는 앞으로 올 때의 새 실행·보관함 전체 다시 비교마다 미룬 장을 다시 남은 일로 세므로, 보관함 수가 늘지 않았고 남은 일이
///   축하 때 미룬 수 이하인 진행률은 축하를 지우지 않는다(머무는 시간을 채운다). 한계: 뒤에서 미룬 장(BG 모드 분류 미룸 포함)을
///   앞 새 실행이 실제로 처리할 때 진행 카드가 최대 머무는 시간만큼 늦게 보이고, 2단계에서 보관함에 없다고 나온 장이 다시 대기로
///   돌아오면 새 일로 보아 축하를 지운다.
@MainActor
@Observable
final class LibraryIndexingCelebration {
  /// 화면에 보일 축하. 머무는 시간이 지나거나 진행 카드·멈춤 카드가 대신하면 nil.
  private(set) var current: IndexingCelebration?

  /// 앱이 뒤에 있는 동안 다 한 축하. 앞으로 오면 `current` 가 된다.
  @ObservationIgnored private var pending: IndexingCelebration?
  /// 이번 세대 첫 진행률. 무장 판정과 끝낸 수의 기준이다.
  @ObservationIgnored private var baseline: IndexingProgress?
  /// 첫 진행률의 남은 일이 기준 이상이었고 아직 다 함을 받지 않았다.
  @ObservationIgnored private var isArmed = false
  /// 이번 세대의 지난 실행(`IndexingClient.run()`)들에서 읽은 글자 수 합. 기준을 잡을 때 기준의 읽은 글자 수를 빼고 시작해
  /// 이미 돌던 실행에 붙었을 때 붙기 전에 읽은 글자를 세지 않는다.
  @ObservationIgnored private var recognizedInEarlierRuns = 0
  /// 지금 실행에서 마지막으로 받은 읽은 글자 수. 실행이 바뀔 때(`runStarted()`, 또는 같은 구독에서 받은 값이 줄었을 때) 위 합에 더한다.
  @ObservationIgnored private var lastRecognizedInRun = 0
  /// 축하를 만든 다 함 진행률의 미룬 수(`skippedCount + skippedTextCount`). 축하 중 끝나지 않은 진행률의 남은 일이 이 값 이하면
  /// 다시 비교로 미룬 장이 남은 일로 돌아온 것으로 보고 축하를 남긴다. 축하가 있을 때만 뜻이 있다.
  @ObservationIgnored private var deferredAtCelebration = 0
  /// 축하를 만든 다 함 진행률의 보관함 수(`totalCount`). 축하 중 이보다 늘면 새 사진이라 축하를 지운다.
  @ObservationIgnored private var totalAtCelebration = 0
  @ObservationIgnored private var nextID = 0
  /// 머무는 시간을 재라는 요청(축하 id). `run(_:generation:)` 이 도는 동안만 있다. 없으면 화면이 사라진 것이라 축하를 버린다.
  @ObservationIgnored private var dwellRequests: AsyncStream<Int>.Continuation?
  /// `begin()` 마다 오른다. 끝난 지난 세대의 루프가 새 세대의 상태를 지우지 않게 한다.
  @ObservationIgnored private var loopGeneration = 0
  @ObservationIgnored private let minimumWork: Int
  @ObservationIgnored private let dwell: Duration
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

  init(minimumWork: Int, dwell: Duration, sleep: @escaping @Sendable (Duration) async throws -> Void) {
    self.minimumWork = minimumWork
    self.dwell = dwell
    self.sleep = sleep
  }

  /// 새 세대를 시작한다. 화면 진입이 task group 을 열기 전에 동기로 부른다(그룹 안 자식 Task 의 시작 순서는 정해져 있지 않아,
  /// 인덱서가 진행률을 바로 보내도 머무는 시간 통로가 있게 한다). 돌려준 통로는 `run(_:generation:)` 에 넘긴다.
  func begin() -> (requests: AsyncStream<Int>, generation: Int) {
    self.current = nil
    self.pending = nil
    self.baseline = nil
    self.isArmed = false
    self.recognizedInEarlierRuns = 0
    self.lastRecognizedInRun = 0
    self.deferredAtCelebration = 0
    self.totalAtCelebration = 0
    self.loopGeneration += 1
    self.dwellRequests?.finish()
    let (requests, continuation) = AsyncStream.makeStream(of: Int.self)
    self.dwellRequests = continuation
    return (requests, self.loopGeneration)
  }

  /// 축하마다 머무는 시간을 잰 뒤 그 축하가 아직 보이면 접는다. 화면 진입 Task 가 취소되면(화면이 사라짐) 끝나고,
  /// 자기 세대면 보이던·미룬 축하를 버린다.
  func run(_ requests: AsyncStream<Int>, generation: Int) async {
    for await id in requests {
      do {
        try await self.sleep(self.dwell)
      } catch {
        break
      }
      // 잠든 사이 진행 카드가 대신했거나 다른 축하로 바뀌었으면 건드리지 않는다.
      if self.current?.id == id {
        self.current = nil
      }
    }
    guard generation == self.loopGeneration else { return }
    self.current = nil
    self.pending = nil
    self.dwellRequests = nil
  }

  /// 화면 진입의 다른 일이 모두 끝났다(더 올 진행률이 없다). 자기 세대면 머무는 시간 통로를 닫는다. 이미 받은 요청은
  /// `run(_:generation:)` 이 머무는 시간을 채운 뒤 끝나고, 이후 축하(뒤에서 미룬 것 포함)는 버린다.
  func end(generation: Int) {
    guard generation == self.loopGeneration else { return }
    self.dwellRequests?.finish()
    self.dwellRequests = nil
  }

  /// 인덱서의 실행(`IndexingClient.run()`)을 시작한다(첫 실행·다시 시도 모두). 지난 실행에서 읽은 글자 수를 합에 넣는다.
  func runStarted() {
    self.recognizedInEarlierRuns += self.lastRecognizedInRun
    self.lastRecognizedInRun = 0
  }

  /// 진행률을 받았다. `LibraryModel` 이 `indexingProgress` 를 바꾼 같은 턴에 부른다.
  func progressReceived(_ progress: IndexingProgress, isSceneActive: Bool) {
    if self.baseline == nil {
      self.baseline = progress
      self.recognizedInEarlierRuns = -progress.recognizedTextCount
      self.isArmed = !progress.isFinished && Self.remainingWork(progress) >= self.minimumWork
    }
    // 인덱서는 같은 구독 안에서도 실행을 갈아 끼운다(앞으로 올 때 BG 모드 실행을 새 실행으로 등).
    // 한계: 뒤에 있는 동안은 진행률을 받지 않아, BG 처리 작업의 새 실행이 앞 실행 값 이상을 읽으면 줄어듦을 못 보고 적게 센다(docs/ARCHITECTURE.md §4 인덱싱).
    // 새 실행은 읽은 글자 수를 0 부터 다시 세므로, 줄었으면 실행이 바뀐 것으로 보고 지난 실행 값을 합에 넣는다.
    if progress.recognizedTextCount < self.lastRecognizedInRun {
      self.recognizedInEarlierRuns += self.lastRecognizedInRun
    }
    self.lastRecognizedInRun = progress.recognizedTextCount
    guard progress.isFinished else {
      // 새 일(보관함 수가 늘었거나 남은 일이 축하 때 미룬 수보다 많음)이면 진행 카드가 이긴다. 축하가 있었으면 무장은 이미 풀려 이 진행이 끝나도
      // 다시 축하하지 않는다(세대당 한 번). 축하 전이면 무장은 그대로라 이 진행이 끝나면 축하할 수 있다.
      // 아니면 다시 비교(앞으로 올 때의 새 실행·보관함 전체 다시 비교)가 미룬 장을 다시 남은 일로 센 것이라 축하를 남긴다.
      // 머무는 시간은 처음 보일 때 한 번만 재므로 여기서 새로 걸지 않는다.
      let hasNewWork = progress.totalCount > self.totalAtCelebration
        || Self.remainingWork(progress) > self.deferredAtCelebration
      if hasNewWork {
        self.current = nil
        self.pending = nil
      }
      return
    }
    // 무장하지 않은 다 함, 축하 중 같은 값 다 함은 아무것도 하지 않는다(머무는 시간을 늘리지 않는다).
    guard self.isArmed, let baseline = self.baseline else { return }
    self.isArmed = false
    let completed = Self.completedWork(
      baseline: baseline,
      latest: progress,
      recognizedInEarlierRuns: self.recognizedInEarlierRuns
    )
    guard completed >= self.minimumWork else { return }
    self.nextID += 1
    let celebration = IndexingCelebration(id: self.nextID)
    self.deferredAtCelebration = progress.skippedCount + progress.skippedTextCount
    self.totalAtCelebration = progress.totalCount
    if isSceneActive {
      self.show(celebration)
    } else {
      self.pending = celebration
    }
  }

  /// 앱이 앞으로 왔다. 뒤에서 미룬 축하를 보이고, 머무는 시간은 이때부터 잰다.
  func sceneBecameActive() {
    guard let pending = self.pending else { return }
    self.pending = nil
    self.show(pending)
  }

  /// 인덱싱이 멈췄다. 멈춤 카드가 대신하므로 보이던·미룬 축하를 버린다(버린 축하는 이번 세대에서 다시 나오지 않는다). 축하를 만들기 전
  /// 무장한 채 멈췄으면 무장은 그대로라 다시 시도로 끝까지 가면 축하한다.
  func indexingStopped() {
    self.current = nil
    self.pending = nil
  }

  /// 남은 일: 1단계에서 아직 분류하지 않은 수(미룬 수 제외) + 2단계 대기 수.
  static func remainingWork(_ progress: IndexingProgress) -> Int {
    max(progress.totalCount - progress.indexedCount - progress.skippedCount, 0) + progress.pendingTextCount
  }

  /// 이번 세대에서 실제로 끝낸 수: 기준보다 늘어난 1단계 저장 수 + 이번 세대에 읽은 글자 수.
  /// 1단계 저장 수는 미룬 장을 세지 않으므로 iCloud 에만 있는 장은 들지 않는다. 처리 중 사진이 지워지면 적게 잡힌다(축하하지 않는 쪽).
  /// - Parameter recognizedInEarlierRuns: 지난 실행들에서 읽은 글자 수 합에서 기준의 읽은 글자 수를 뺀 값.
  static func completedWork(
    baseline: IndexingProgress,
    latest: IndexingProgress,
    recognizedInEarlierRuns: Int
  ) -> Int {
    let classified = max(latest.indexedCount - baseline.indexedCount, 0)
    return max(classified + recognizedInEarlierRuns + latest.recognizedTextCount, 0)
  }

  /// 머무는 시간 통로가 없으면(화면이 사라짐) 버린다.
  private func show(_ celebration: IndexingCelebration) {
    guard let dwellRequests = self.dwellRequests else { return }
    self.current = celebration
    dwellRequests.yield(celebration.id)
  }
}
