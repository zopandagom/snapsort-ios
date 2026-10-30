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
  private let log: EventLog
  private let progress: [IndexingProgress]
  private let result: IndexingBackgroundResult
  /// nil 이면 진행률을 보낸 뒤 바로 돌아오고, 있으면 열리거나 취소될 때까지 기다린다.
  private let gate: Gate?
  private let shouldYield = Mutex<(@Sendable () -> Bool)?>(nil)

  init(
    log: EventLog,
    progress: [IndexingProgress] = [],
    result: IndexingBackgroundResult = IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: false),
    gate: Gate? = nil
  ) {
    self.log = log
    self.progress = progress
    self.result = result
    self.gate = gate
  }

  /// 마지막 `runInBackground` 에 넘긴 양보 확인을 지금 부른 값.
  var shouldYieldNow: Bool? {
    self.shouldYield.withLock { $0 }?()
  }

  func run() -> AsyncStream<IndexingProgress> {
    AsyncStream { $0.finish() }
  }

  func appActivityChanged(isActive: Bool) {
    self.log.append("activity(\(isActive))")
  }

  func waitUntilStoreReleased() async {
    self.log.append("waitUntilStoreReleased")
  }

  func runInBackground(
    shouldYield: @escaping @Sendable () -> Bool,
    progress: @escaping @Sendable (IndexingProgress) -> Void
  ) async -> IndexingBackgroundResult {
    self.log.append("runInBackground")
    self.shouldYield.withLock { $0 = shouldYield }
    for value in self.progress {
      progress(value)
    }
    if let gate = self.gate, await !gate.wait() {
      self.log.append("runInBackground.cancelled")
      return IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false)
    }
    return self.result
  }
}

final class TripPlaceDouble: TripPlaceClient {
  private let log: EventLog
  private let gate: Gate?

  init(log: EventLog, gate: Gate? = nil) {
    self.log = log
    self.gate = gate
  }

  func prefetchPlaces(locale _: Locale) async {
    self.log.append("prefetch")
    if let gate = self.gate, await !gate.wait() {
      self.log.append("prefetch.cancelled")
    }
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

  private let log: EventLog
  var submitError: (any Error)?
  private(set) var registeredIdentifiers: [String] = []
  private(set) var submissions: [Submission] = []
  private var handler: (@MainActor (any BackgroundProcessingTask) -> Void)?

  init(log: EventLog) {
    self.log = log
  }

  func register(identifier: String, handler: @escaping @MainActor (any BackgroundProcessingTask) -> Void) -> Bool {
    self.registeredIdentifiers.append(identifier)
    self.handler = handler
    return true
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

  let log: EventLog
  let scheduler: SchedulerDouble
  let application: ApplicationDouble
  let thermal: ThermalDouble
  let impl: BackgroundIndexingClientImpl

  init(
    log: EventLog = EventLog(),
    indexing: (EventLog) -> IndexingDouble? = { IndexingDouble(log: $0) },
    tripPlace: (EventLog) -> TripPlaceDouble? = { TripPlaceDouble(log: $0) },
    taskIdentifier: String? = Coordinator.identifier,
    isActive: Bool = true
  ) {
    self.log = log
    self.scheduler = SchedulerDouble(log: log)
    self.application = ApplicationDouble(log: log, isActive: isActive)
    let thermal = ThermalDouble()
    self.thermal = thermal
    self.impl = BackgroundIndexingClientImpl(
      indexing: indexing(log),
      tripPlace: tripPlace(log),
      widgetTimeline: WidgetTimelineDouble(log: log),
      taskIdentifier: taskIdentifier,
      locale: { Locale(identifier: "ko_KR") },
      scheduler: self.scheduler,
      application: self.application,
      thermalState: { thermal.value }
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
