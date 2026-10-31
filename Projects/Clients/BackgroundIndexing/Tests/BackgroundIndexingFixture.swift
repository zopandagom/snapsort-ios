import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import Synchronization
import Testing
import TripPlaceInterface
import WidgetTimelineInterface
@testable import BackgroundIndexingImpl

// 조정자 테스트용 대역. 여러 Client 에 걸친 호출 순서를 한 기록(`EventLog`)에 남긴다.

/// 대역들이 함께 쓰는 호출 기록. 분류·미리 받기 대역은 MainActor 밖에서도 불리므로 Mutex 로 보호한다.
final class EventLog: Sendable {
  private let events = Mutex<[String]>([])

  var all: [String] {
    self.events.withLock { $0 }
  }

  func append(_ event: String) {
    self.events.withLock { $0.append(event) }
  }

  func count(_ event: String) -> Int {
    self.all.count { $0 == event }
  }

  /// 기록에서 `event` 가 처음 나온 위치. 없으면 nil.
  func index(of event: String) -> Int? {
    self.all.firstIndex(of: event)
  }
}

/// 풀거나 기다리는 쪽이 취소될 때까지 매달리는 문.
final class Gate: Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: Void.self)
  }

  func open() {
    self.continuation.finish()
  }

  /// 열리면 true, 기다리던 Task 가 취소되면 false.
  func wait() async -> Bool {
    for await _ in self.stream {}
    return !Task.isCancelled
  }
}

final class IndexingDouble: IndexingClient {
  /// `runInBackground` 호출 하나의 동작: 진행률을 보낸 뒤 문이 있으면 열리거나 취소될 때까지 매달리고, 없으면 결과로 돌아온다.
  struct Call: Sendable {
    var progress: [IndexingProgress] = []
    var result = IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: false)
    var gate: Gate?
  }

  private struct State {
    var calls = 0
    var shouldYield: (@Sendable () -> Bool)?
    var running: (@Sendable (IndexingProgress) -> Void)?
  }

  private let log: EventLog
  private let defaultCall: Call
  private let calls: [Call]
  /// 있으면 `waitUntilStoreReleased` 가 열릴 때까지 기다린다.
  private let releaseGate: Gate?
  private let state = Mutex(State())

  /// - Parameter calls: 부른 순서대로 쓸 동작. 다 쓰면 `progress`·`result`·`gate` 로 만든 동작을 쓴다.
  init(
    log: EventLog,
    progress: [IndexingProgress] = [],
    result: IndexingBackgroundResult = IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: false),
    gate: Gate? = nil,
    calls: [Call] = [],
    releaseGate: Gate? = nil
  ) {
    self.log = log
    self.defaultCall = Call(progress: progress, result: result, gate: gate)
    self.calls = calls
    self.releaseGate = releaseGate
  }

  /// 마지막 `runInBackground` 에 넘긴 양보 확인을 지금 부른 값.
  var shouldYieldNow: Bool? {
    self.state.withLock { $0.shouldYield }?()
  }

  /// 마지막 `runInBackground` 의 진행률 콜백에 값을 하나 보낸다(돌아온 뒤에도 보낸다. 실행기는 hold 를 놓으면 보내지 않으므로 그 전에 부른다).
  func sendProgress(_ progress: IndexingProgress) {
    self.state.withLock { $0.running }?(progress)
  }

  func run() -> AsyncStream<IndexingProgress> {
    AsyncStream { $0.finish() }
  }

  func appActivityChanged(isActive: Bool) {
    self.log.append("activity(\(isActive))")
  }

  func waitUntilStoreReleased() async {
    self.log.append("waitUntilStoreReleased")
    if let releaseGate {
      _ = await releaseGate.wait()
    }
  }

  func runInBackground(
    shouldYield: @escaping @Sendable () -> Bool,
    progress: @escaping @Sendable (IndexingProgress) -> Void
  ) async -> IndexingBackgroundResult {
    let index = self.state.withLock { state in
      defer { state.calls += 1 }
      state.shouldYield = shouldYield
      state.running = progress
      return state.calls
    }
    self.log.append("runInBackground")
    let call = index < self.calls.count ? self.calls[index] : self.defaultCall
    for value in call.progress {
      progress(value)
    }
    if let gate = call.gate, await !gate.wait() {
      self.log.append("runInBackground.cancelled")
      return IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false)
    }
    return call.result
  }
}

final class WidgetTimelineDouble: WidgetTimelineClient {
  private let log: EventLog

  init(log: EventLog) {
    self.log = log
  }

  func reloadExpiryWidget() {
    self.log.append("widget")
  }
}

@MainActor
final class SchedulerDouble: BackgroundTaskScheduling {
  struct Submission: Equatable {
    let identifier: String
    let requiresExternalPower: Bool
    let requiresNetworkConnectivity: Bool
  }

  struct ContinuedSubmission: Equatable {
    let identifier: String
    let title: String
    let subtitle: String
  }

  private let log: EventLog
  var submitError: (any Error)?
  var continuedRegisterResult = true
  var continuedSubmitError: (any Error)?
  private(set) var registeredIdentifiers: [String] = []
  private(set) var registeredContinuedIdentifiers: [String] = []
  private(set) var submissions: [Submission] = []
  private(set) var continuedSubmissions: [ContinuedSubmission] = []
  private var handler: (@MainActor (any BackgroundProcessingTask) -> Void)?
  private var continuedHandler: (@MainActor (any ContinuedProcessingTask) -> Void)?

  init(log: EventLog) {
    self.log = log
  }

  func register(identifier: String, handler: @escaping @MainActor (any BackgroundProcessingTask) -> Void) -> Bool {
    self.registeredIdentifiers.append(identifier)
    self.handler = handler
    return true
  }

  func registerContinued(
    identifier: String,
    handler: @escaping @MainActor (any ContinuedProcessingTask) -> Void
  ) -> Bool {
    self.registeredContinuedIdentifiers.append(identifier)
    self.continuedHandler = handler
    return self.continuedRegisterResult
  }

  func submitContinued(identifier: String, title: String, subtitle: String) throws {
    self.log.append("submitContinued")
    self.continuedSubmissions.append(ContinuedSubmission(identifier: identifier, title: title, subtitle: subtitle))
    if let error = self.continuedSubmitError {
      throw error
    }
  }

  func submit(identifier: String, requiresExternalPower: Bool, requiresNetworkConnectivity: Bool) throws {
    self.log.append("submit")
    self.submissions.append(Submission(
      identifier: identifier,
      requiresExternalPower: requiresExternalPower,
      requiresNetworkConnectivity: requiresNetworkConnectivity
    ))
    if let submitError = self.submitError {
      throw submitError
    }
  }

  /// 시스템이 작업을 실행한 것처럼 등록한 핸들러를 부른다.
  func launch(_ task: TaskDouble) {
    self.handler?(task)
  }

  /// 시스템이 계속 처리 작업을 실행한 것처럼 등록한 핸들러를 부른다.
  func launchContinued(_ task: ContinuedTaskDouble) {
    self.continuedHandler?(task)
  }
}

final class TaskDouble: BackgroundProcessingTask {
  private let log: EventLog
  var expirationHandler: (() -> Void)?

  init(log: EventLog) {
    self.log = log
  }

  func setTaskCompleted(success: Bool) {
    self.log.append("completed(\(success))")
  }

  /// 시스템이 작업을 끝내려는 것처럼 만료 핸들러를 부른다.
  func expire() {
    self.expirationHandler?()
  }
}

@MainActor
final class ApplicationDouble: BackgroundExecution {
  private let log: EventLog
  var isActive: Bool
  private var nextIdentifier = 1
  private var expiration: (@MainActor () -> Void)?

  init(log: EventLog, isActive: Bool = true) {
    self.log = log
    self.isActive = isActive
  }

  func begin(name _: String, expiration: @escaping @MainActor () -> Void) -> Int? {
    let identifier = self.nextIdentifier
    self.nextIdentifier += 1
    self.expiration = expiration
    self.log.append("begin(\(identifier))")
    return identifier
  }

  func end(_ identifier: Int) {
    self.log.append("end(\(identifier))")
  }

  /// 빌린 시간이 끝나려는 것처럼 만료 핸들러를 부른다.
  func expireAssertion() {
    self.expiration?()
  }
}

/// 발열 상태 대역. 분류 대역이 MainActor 밖에서 읽는다.
final class ThermalDouble: Sendable {
  private let state = Mutex(ProcessInfo.ThermalState.nominal)

  var value: ProcessInfo.ThermalState {
    get { self.state.withLock { $0 } }
    set { self.state.withLock { $0 = newValue } }
  }
}

@MainActor
struct Coordinator {
  static let identifier = "com.zopandagom.snapsort.indexing"
  static let continuedIdentifier = "com.zopandagom.snapsort.continuedIndexing.run"

  let log: EventLog
  let scheduler: SchedulerDouble
  let application: ApplicationDouble
  let thermal: ThermalDouble
  let indexing: IndexingDouble?
  let tripPlace: TripPlaceDouble?
  let impl: BackgroundIndexingClientImpl

  init(
    log: EventLog = EventLog(),
    indexing: (EventLog) -> IndexingDouble? = { IndexingDouble(log: $0) },
    tripPlace: (EventLog) -> TripPlaceDouble? = { TripPlaceDouble(log: $0) },
    taskIdentifier: String? = Coordinator.identifier,
    continuedIdentifier: String? = Coordinator.continuedIdentifier,
    isActive: Bool = true,
    meterWeights: ContinuedIndexingMeter.Weights = .unit
  ) {
    self.log = log
    self.scheduler = SchedulerDouble(log: log)
    self.application = ApplicationDouble(log: log, isActive: isActive)
    let thermal = ThermalDouble()
    self.thermal = thermal
    self.indexing = indexing(log)
    self.tripPlace = tripPlace(log)
    self.impl = BackgroundIndexingClientImpl(
      indexing: self.indexing,
      tripPlace: self.tripPlace,
      widgetTimeline: WidgetTimelineDouble(log: log),
      taskIdentifier: taskIdentifier,
      continuedTaskIdentifier: continuedIdentifier,
      locale: { Locale(identifier: "ko_KR") },
      scheduler: self.scheduler,
      application: self.application,
      thermalState: { thermal.value },
      meterWeights: meterWeights
    )
  }

  /// 등록하고 작업 하나를 실행한다.
  func launch() -> TaskDouble {
    self.impl.registerLaunchHandler()
    let task = TaskDouble(log: self.log)
    self.scheduler.launch(task)
    return task
  }
}

extension IndexingProgress {
  static let classifying = IndexingProgress(totalCount: 10, indexedCount: 2, skippedCount: 0)
  static let recognizingText = IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, pendingTextCount: 3)
  /// `recognizingText` 다음 끝(글자 3장 읽음).
  static let finished = IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, recognizedTextCount: 3)
}

/// 조건이 될 때까지 짧게 잠들며 기다린다. 조정자의 Task 는 끝나는 시점이 스케줄링에 달렸으므로 시간으로 제한한다
/// (TripPlaceFixture 의 같은 함수와 같은 방식).
@MainActor
func waitUntil(timeout: Duration = .seconds(30), _ condition: () -> Bool) async {
  let deadline = ContinuousClock.now + timeout
  while !condition(), ContinuousClock.now < deadline {
    do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
  }
  #expect(condition(), "기다리던 상태가 되지 않았다")
}
