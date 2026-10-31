import BackgroundIndexingInterface
import Foundation
import Synchronization
import TripPlaceInterface
@testable import BackgroundIndexingImpl

// 미리 받기 회차·계속 처리 작업 대역과 계속 처리 테스트 도우미.

final class TripPlaceDouble: TripPlaceClient {
  /// 회차 하나의 동작: 진행 알림을 보낸 뒤 문이 있으면 열리거나 취소될 때까지 매달린다.
  struct Round: Sendable {
    var progress: [TripPlacePrefetchProgress] = []
    var gate: Gate?
  }

  private struct State {
    var calls = 0
    var running: (@Sendable (TripPlacePrefetchProgress) -> Void)?
  }

  private let log: EventLog
  private let gate: Gate?
  private let rounds: [Round]
  private let state = Mutex(State())

  /// - Parameters:
  ///   - gate: `rounds` 에 없는 회차가 매달리는 문.
  ///   - rounds: 부른 순서대로 쓸 회차 동작. 다 쓰면 `gate` 로 매달리고 알림을 보내지 않는다.
  init(log: EventLog, gate: Gate? = nil, rounds: [Round] = []) {
    self.log = log
    self.gate = gate
    self.rounds = rounds
  }

  func prefetchPlaces(locale _: Locale, progress: @escaping @Sendable (TripPlacePrefetchProgress) -> Void) async {
    let index = self.state.withLock { state in
      defer { state.calls += 1 }
      state.running = progress
      return state.calls
    }
    self.log.append("prefetch")
    let round = index < self.rounds.count ? self.rounds[index] : Round(gate: self.gate)
    for value in round.progress {
      progress(value)
    }
    if let gate = round.gate, await !gate.wait() {
      self.log.append("prefetch.cancelled")
    }
    self.state.withLock { $0.running = nil }
  }

  /// 도는 회차의 진행 콜백에 값을 하나 보낸다. 도는 회차가 없으면 버린다.
  func sendPrefetchProgress(_ progress: TripPlacePrefetchProgress) {
    self.state.withLock { $0.running }?(progress)
  }

  func placeChanges() async -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }

  func holdStoreAccess() async {
    self.log.append("hold")
  }

  func allowStoreAccess() async {
    self.log.append("allow")
  }
}

/// 계속 처리 작업 대역. 진행률·문구·완료를 같은 기록에 남긴다.
final class ContinuedTaskDouble: ContinuedProcessingTask {
  private let log: EventLog
  var expirationHandler: (() -> Void)?

  init(log: EventLog) {
    self.log = log
  }

  /// 처리 작업(`completed(…)`)과 겹칠 때 구분하도록 이름을 달리 남긴다.
  func setTaskCompleted(success: Bool) {
    self.log.append("continuedCompleted(\(success))")
  }

  func updateTitle(_ title: String, subtitle: String) {
    self.log.append("title(\(title),\(subtitle))")
  }

  func updateProgress(completed: Int64, total: Int64) {
    self.log.append("progress(\(completed),\(total))")
  }

  /// 시스템이 끝내려는 것처럼(사용자 취소 포함) 만료 핸들러를 부른다.
  func expire() {
    self.expirationHandler?()
  }
}

@MainActor
extension Coordinator {
  /// 등록하고 앞에서 계속 처리를 요청한 뒤 시스템이 그 작업을 실행한 것처럼 핸들러를 부른다.
  func launchContinued() -> ContinuedTaskDouble {
    self.impl.registerLaunchHandler()
    _ = self.impl.requestContinuedIndexing(text: .test)
    let task = ContinuedTaskDouble(log: self.log)
    self.scheduler.launchContinued(task)
    return task
  }

  /// 계속 처리 작업의 진행 표시 기록(`progress(…)`·`title(…)`)만.
  var displayLog: [String] {
    self.log.all.filter { $0.hasPrefix("progress(") || $0.hasPrefix("title(") }
  }
}

extension ContinuedIndexingText {
  /// 단계 이름과 "처리/전체" 를 그대로 쓰는 테스트 문구.
  static let test = ContinuedIndexingText(
    title: { "\($0.stage)" },
    subtitle: { "\($0.doneCount)/\($0.totalCount)" }
  )
}

extension ContinuedIndexingMeter.Weights {
  /// 모든 단위 1, 글자 예약·장소 예약 없음: 진행 표시가 실제 장·키 개수의 합이 된다(가중 전 계산과 같은 수).
  /// 사전 무게가 매우 커서 글자 비율 추정이 0 에 머물러(테스트의 개수에서는 반올림하면 0) 남은 분류에 글자 몫을 넣지 않는다.
  static let unit = Self(
    classify: 1,
    text: 1,
    placeKey: 1,
    textShare: 0,
    textSharePrior: 1_000_000_000,
    placeReserveKeys: 0
  )
}
