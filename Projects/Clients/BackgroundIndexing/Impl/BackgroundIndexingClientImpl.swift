import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import TripPlaceInterface
import WidgetTimelineInterface
#if DEBUG
  import os
#endif

/// BG 작업(`BGProcessingTask`)과 앱이 뒤로 갈 때의 멈춤을 맞추는 조정자 (docs/ARCHITECTURE.md §4 인덱싱).
/// 분류와 미리 받기가 저장소에서 손을 뗀 뒤에만 빌린 실행 시간을 돌려주고 BG 작업 완료를 알린다(잠금을 쥔 채 정지 방지).
/// 저장소 출입 맞추기(settle)는 요청 순서대로 하나씩 하고, 적용할 때의 상태(`isStoreAllowed`)를 읽는다. 그래서 빨리 복귀했는데
/// 앞서 요청한 막음이 나중에 적용되는 일이 없다.
@MainActor
public final class BackgroundIndexingClientImpl: BackgroundIndexingClient {
  /// 처리 중인 BG 작업 하나.
  private final class TaskContext {
    let task: any BackgroundProcessingTask
    var work: Task<IndexingBackgroundResult, Never>?
    var isExpired = false
    var isCompleted = false
    #if DEBUG
      let startedAt = ContinuousClock.now
    #endif

    init(task: any BackgroundProcessingTask) {
      self.task = task
    }

    /// 완료는 한 번만 알린다.
    func complete(success: Bool) {
      guard !self.isCompleted else { return }
      self.isCompleted = true
      self.task.setTaskCompleted(success: success)
    }
  }

  /// 앱이 뒤로 갈 때 빌리는 실행 시간의 이름(시스템 로그용 고정 문자열).
  static let pauseAssertionName = "SnapSort.indexing.pause"

  private let indexing: (any IndexingClient)?
  private let tripPlace: (any TripPlaceClient)?
  private let widgetTimeline: any WidgetTimelineClient
  private let taskIdentifier: String?
  private let locale: @Sendable () -> Locale
  private let scheduler: any BackgroundTaskScheduling
  private let application: any BackgroundExecution
  private let thermalState: @Sendable () -> ProcessInfo.ThermalState

  private var isAppActive = true
  private var activeTask: TaskContext?
  /// 앱이 뒤로 갈 때 빌린 실행 시간.
  private var assertion: Int?
  private var isRegistered = false
  /// 마지막으로 요청한 저장소 출입 맞추기. 다음 요청은 이것이 끝난 뒤 적용한다.
  private var lastSettle: Task<Void, Never>?

  /// - Parameters:
  ///   - indexing: 분류 인덱서. 저장소를 열지 못하면 nil 이고, 그때 BG 작업은 바로 실패로 끝내고 다시 예약한다.
  ///   - tripPlace: 여행 장소 이름 미리 받기. 보관함 화면과 같은 인스턴스여야 빈도 제한이 이어진다.
  ///   - widgetTimeline: BG 실행이 저장소에 썼을 때(여행 교체 제외, `IndexingBackgroundResult.didChangeStore`) 끝나기 전에 한 번 위젯 갱신을 요청한다.
  ///   - taskIdentifier: Info.plist `BGTaskSchedulerPermittedIdentifiers` 의 식별자. nil 이면 등록·제출하지 않는다.
  ///   - locale: 미리 받기 로캘. 회차를 시작할 때 한 번 읽는다.
  public convenience init(
    indexing: (any IndexingClient)?,
    tripPlace: (any TripPlaceClient)?,
    widgetTimeline: any WidgetTimelineClient,
    taskIdentifier: String?,
    locale: @escaping @Sendable () -> Locale = { .current }
  ) {
    self.init(
      indexing: indexing,
      tripPlace: tripPlace,
      widgetTimeline: widgetTimeline,
      taskIdentifier: taskIdentifier,
      locale: locale,
      scheduler: SystemBackgroundTaskScheduler(),
      application: SystemBackgroundExecution(),
      thermalState: { ProcessInfo.processInfo.thermalState }
    )
  }

  init(
    indexing: (any IndexingClient)?,
    tripPlace: (any TripPlaceClient)?,
    widgetTimeline: any WidgetTimelineClient,
    taskIdentifier: String?,
    locale: @escaping @Sendable () -> Locale,
    scheduler: any BackgroundTaskScheduling,
    application: any BackgroundExecution,
    thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState
  ) {
    self.indexing = indexing
    self.tripPlace = tripPlace
    self.widgetTimeline = widgetTimeline
    self.taskIdentifier = taskIdentifier
    self.locale = locale
    self.scheduler = scheduler
    self.application = application
    self.thermalState = thermalState
  }

  /// BG 작업 핸들러를 등록한다. 앱이 실행을 마치기 전(App init)에 한 번 부른다. 식별자가 nil 이면 아무것도 하지 않고,
  /// 두 번째 호출은 무시한다(같은 식별자를 두 번 등록하면 앱이 죽는다). 저장소가 없어도 등록한다(예약된 작업이 핸들러 없이 오지 않게).
  public func registerLaunchHandler() {
    guard !self.isRegistered, let identifier = self.taskIdentifier else { return }
    self.isRegistered = true
    let isRegistered = self.scheduler.register(identifier: identifier) { task in
      self.handle(task)
    }
    #if DEBUG
      Self.logger.notice("register registered=\(isRegistered ? 1 : 0, privacy: .public)")
    #else
      _ = isRegistered
    #endif
  }

  // MARK: - BackgroundIndexingClient

  public func appDidEnterBackground() {
    guard self.isAppActive else { return }
    self.isAppActive = false
    self.indexing?.appActivityChanged(isActive: false)
    // BG 작업이 도는 중이면 그 작업이 실행을 쥐고 완료 전에 저장소에서 손 뗀다.
    if self.activeTask == nil {
      self.beginAssertion()
      // 뒤에 있는 동안 찍은 새 사진도 분류하도록 할 일 판정 없이 늘 제출한다. 할 일이 없으면 BG 실행은 바로 끝난다.
      if self.indexing != nil {
        self.submit()
      }
    }
    self.requestSettle()
  }

  public func appDidBecomeActive() {
    guard !self.isAppActive else { return }
    self.isAppActive = true
    self.indexing?.appActivityChanged(isActive: true)
    self.requestSettle()
  }

  // MARK: - BG 작업

  private func handle(_ task: any BackgroundProcessingTask) {
    // 드문 중복. 도는 작업이 끝나면 필요할 때 다시 예약한다.
    guard self.activeTask == nil else {
      task.setTaskCompleted(success: false)
      return
    }
    // 저장소를 열지 못했다(첫 잠금 해제 전 등). 다음 기회에 다시 연다.
    guard let indexing = self.indexing else {
      self.submit()
      task.setTaskCompleted(success: false)
      return
    }
    // 시스템이 앱을 띄워 이 핸들러가 먼저 오면 화면 이벤트가 아직 없다. 지금 상태를 직접 읽는다.
    self.isAppActive = self.application.isActive
    indexing.appActivityChanged(isActive: self.isAppActive)
    #if DEBUG
      let thermal = self.thermalState().rawValue
      Self.logger.notice(
        "start active=\(self.isAppActive ? 1 : 0, privacy: .public) thermal=\(thermal, privacy: .public)"
      )
    #endif
    guard !Self.isHot(self.thermalState()) else {
      self.submit()
      task.setTaskCompleted(success: true)
      return
    }
    let context = TaskContext(task: task)
    self.activeTask = context
    // 앱이 뒤로 갈 때 빌린 시간이 남았으면 이제 이 작업이 실행을 쥔다.
    self.endAssertion()
    // 시스템이 만료 핸들러를 어느 스레드에서 부르는지 헤더가 정하지 않는다(BGTask.h). MainActor 메서드 안의 클로저는
    // MainActor 로 추론되어 메인 밖에서 불리면 런타임 격리 확인에 걸리므로, 격리 없는 `@Sendable` 클로저로 두고
    // Sendable 인 작업 식별만 잡아 메인으로 넘긴다.
    let taskID = ObjectIdentifier(task)
    task.expirationHandler = { @Sendable [weak self] in
      Task { @MainActor in self?.expireActiveTask(taskID) }
    }
    self.requestSettle()
    context.work = Task { await self.runWork(indexing: indexing) }
    Task { await self.finish(context) }
  }

  /// 분류를 쥐고, 1단계를 마친 진행률이 오면 미리 받기 회차를 한 번 돌린다. 분류가 먼저 끝나도 회차는 끝까지 간다.
  private func runWork(indexing: any IndexingClient) async -> IndexingBackgroundResult {
    let (classified, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let thermalState = self.thermalState
    let tripPlace = self.tripPlace
    let locale = self.locale
    return await withTaskGroup(of: IndexingBackgroundResult?.self) { group in
      group.addTask {
        let result = await indexing.runInBackground(
          shouldYield: { Self.isHot(thermalState()) },
          progress: { progress in
            if progress.phase != .classifying {
              continuation.yield()
            }
          }
        )
        continuation.finish()
        return result
      }
      group.addTask {
        for await _ in classified {
          await tripPlace?.prefetchPlaces(locale: locale())
          break
        }
        return nil
      }
      var result: IndexingBackgroundResult?
      for await value in group {
        if let value {
          result = value
        }
      }
      // 분류 쪽은 늘 값을 돌려준다. 혹시 없으면 남은 것으로 보고 다시 예약한다.
      return result ?? IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false)
    }
  }

  /// 실행·미리 받기가 저장소에서 손 뗀 뒤에만 완료를 알린다. 순서: 손 뗌 → 위젯 갱신 요청 → 다시 예약 → 완료.
  private func finish(_ context: TaskContext) async {
    guard let work = context.work else { return }
    let result = await work.value
    self.activeTask = nil
    await self.requestSettle().value
    if result.didChangeStore {
      self.widgetTimeline.reloadExpiryWidget()
    }
    // 다시 시도하려면 완료 전에 제출해야 한다(BGTask.h).
    if context.isExpired || result.hasRemainingWork {
      self.submit()
    }
    #if DEBUG
      let seconds = Int((ContinuousClock.now - context.startedAt).components.seconds)
      Self.logger.notice("""
      end remaining=\(result.hasRemainingWork ? 1 : 0, privacy: .public) \
      changed=\(result.didChangeStore ? 1 : 0, privacy: .public) \
      expired=\(context.isExpired ? 1 : 0, privacy: .public) seconds=\(seconds, privacy: .public)
      """)
    #endif
    context.complete(success: !context.isExpired)
  }

  /// 만료 핸들러가 넘긴 작업이 아직 도는 작업일 때만 만료한다(끝난 작업의 늦은 만료는 버린다).
  private func expireActiveTask(_ taskID: ObjectIdentifier) {
    guard let context = self.activeTask, ObjectIdentifier(context.task) == taskID else { return }
    self.expire(context)
  }

  /// 시스템이 작업을 끝내려 한다. 실행을 취소하면 저장 중 배치가 끝난 뒤 돌아오고, 나머지는 `finish` 가 한다.
  private func expire(_ context: TaskContext) {
    guard !context.isExpired, !context.isCompleted else { return }
    context.isExpired = true
    context.work?.cancel()
    #if DEBUG
      let seconds = Int((ContinuousClock.now - context.startedAt).components.seconds)
      Self.logger.notice("expire seconds=\(seconds, privacy: .public)")
    #endif
  }

  #if DEBUG
    /// Debug 빌드 전용 수치 로그. 정수·고정 문자열만 남긴다(식별자·텍스트·좌표 없음, docs/CONVENTIONS.md §4).
    private static let logger = Logger(subsystem: "com.zopandagom.snapsort", category: "BackgroundIndexing")
  #endif
}

// MARK: - 저장소 출입 맞추기·실행 시간·제출

extension BackgroundIndexingClientImpl {
  /// 앱이 앞에 있거나 BG 작업이 실행을 쥐면 저장소를 쓴다.
  private var isStoreAllowed: Bool {
    self.isAppActive || self.activeTask != nil
  }

  @discardableResult
  private func requestSettle() -> Task<Void, Never> {
    let previous = self.lastSettle
    let settle = Task {
      await previous?.value
      await self.applySettle()
    }
    self.lastSettle = settle
    return settle
  }

  /// 적용하는 동안 상태가 바뀌면 빌린 시간은 그 뒤 요청이 정리한다(막음을 적용하기 전에 돌려주지 않게).
  private func applySettle() async {
    let isAllowed = self.isStoreAllowed
    if isAllowed {
      await self.tripPlace?.allowStoreAccess()
    } else {
      await self.tripPlace?.holdStoreAccess()
      await self.indexing?.waitUntilStoreReleased()
    }
    if self.isStoreAllowed == isAllowed {
      self.endAssertion()
    }
  }

  private func beginAssertion() {
    let previous = self.assertion
    self.assertion = self.application.begin(name: Self.pauseAssertionName) {
      self.endAssertion()
    }
    if let previous {
      self.application.end(previous)
    }
  }

  /// 빌린 시간을 한 번만 돌려준다(만료 핸들러와 맞추기가 겹쳐도).
  private func endAssertion() {
    guard let assertion = self.assertion else { return }
    self.assertion = nil
    self.application.end(assertion)
  }

  /// 충전 중에만, 네트워크 조건 없이 요청한다(오프라인 충전 밤에도 분류. 미리 받기는 네트워크가 있으면 되는 최선 노력).
  private func submit() {
    guard let identifier = self.taskIdentifier else { return }
    do {
      try self.scheduler.submit(identifier: identifier, requiresExternalPower: true, requiresNetworkConnectivity: false)
    } catch {
      // 시뮬레이터(unavailable)·설정 꺼짐·요청 수 초과. 다음 앱 진입 때 앞 실행이 분류한다.
      #if DEBUG
        let code = (error as NSError).code
        Self.logger.notice("submit failed code=\(code, privacy: .public)")
      #endif
    }
  }

  /// `ThermalState` 는 Comparable 이 아니라 목록으로 비교한다.
  nonisolated static func isHot(_ state: ProcessInfo.ThermalState) -> Bool {
    [.serious, .critical].contains(state)
  }
}
