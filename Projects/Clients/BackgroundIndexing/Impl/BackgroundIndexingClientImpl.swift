import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import TripPlaceInterface
import WidgetTimelineInterface
#if DEBUG
  import os
#endif

/// BG 작업(`BGProcessingTask`·`BGContinuedProcessingTask`)과 앱이 뒤로 갈 때의 멈춤을 맞추는 조정자 (docs/ARCHITECTURE.md §4 인덱싱).
/// 분류와 미리 받기가 저장소에서 손을 뗀 뒤에만 빌린 실행 시간을 돌려주고 BG 작업 완료를 알린다(잠금을 쥔 채 정지 방지).
/// 저장소 출입 맞추기(settle)는 요청 순서대로 하나씩 하고, 적용할 때의 상태(`isStoreAllowed`)를 읽는다. 그래서 빨리 복귀했는데
/// 앞서 요청한 막음이 나중에 적용되는 일이 없다.
/// 작업 자리는 종류별로 하나씩이다(`processingTask`, `continuedTask`). 계속 처리 작업은 처리 작업이 돌아도 시작하고(두 hold 가 같은 실행을
/// 함께 쥔다), 계속 처리 작업이 도는 동안 온 처리 작업은 바로 실패로 끝낸다. 계속 처리 쪽은 BackgroundIndexingClientImpl+Continued.
@MainActor
public final class BackgroundIndexingClientImpl: BackgroundIndexingClient {
  /// Info.plist `BGTaskSchedulerPermittedIdentifiers` 에서 읽은 두 식별자.
  public struct TaskIdentifiers: Sendable, Equatable {
    /// 계속 처리 작업을 등록·제출하는 구체 식별자의 접미사(와일드카드 `.*` 자리). 작업은 한 번에 하나라 고정이다.
    static let continuedSuffix = "run"

    /// 처리 작업 식별자: 와일드카드가 아닌 첫 값.
    public let processing: String?
    /// 계속 처리 작업 식별자: `.*` 로 끝나는 첫 값의 `*` 를 `run` 으로 바꾼 것. 시스템은 와일드카드 그대로의 등록을 받지 않는다.
    public let continued: String?

    public init(permitted: [String]) {
      self.processing = permitted.first { !$0.hasSuffix(".*") }
      self.continued = permitted.first { $0.hasSuffix(".*") }.map { String($0.dropLast()) + Self.continuedSuffix }
    }
  }

  /// 앱이 뒤로 갈 때 빌리는 실행 시간의 이름(시스템 로그용 고정 문자열).
  static let pauseAssertionName = "SnapSort.indexing.pause"

  let indexing: (any IndexingClient)?
  let tripPlace: (any TripPlaceClient)?
  let widgetTimeline: any WidgetTimelineClient
  let taskIdentifier: String?
  let continuedTaskIdentifier: String?
  let locale: @Sendable () -> Locale
  let scheduler: any BackgroundTaskScheduling
  let application: any BackgroundExecution
  let thermalState: @Sendable () -> ProcessInfo.ThermalState
  /// 계속 처리 진행 표시의 단위 무게.
  let meterWeights: ContinuedIndexingMeter.Weights

  var isAppActive = true
  /// 처리 작업이 실행기를 쥔 동안.
  var processingTask: TaskContext?
  /// 계속 처리 작업이 실행기·미리 받기를 쥔 동안(핸들러 시작 ~ 실행 끝).
  var continuedTask: TaskContext?
  var continuedPhase = ContinuedPhase.idle
  /// 마지막 계속 처리 요청의 문구. 핸들러가 쓴다.
  var continuedText: ContinuedIndexingText?
  /// 계속 처리 식별자 등록이 됐는지.
  var isContinuedRegistered = false
  /// 계속 처리 제출이 영구 실패했는지(이 실행 동안).
  var isContinuedPermanentlyUnavailable = false
  /// 앱이 뒤로 갈 때 빌린 실행 시간.
  var assertion: Int?
  private var isRegistered = false
  /// 마지막으로 요청한 저장소 출입 맞추기. 다음 요청은 이것이 끝난 뒤 적용한다.
  var lastSettle: Task<Void, Never>?

  /// - Parameters:
  ///   - indexing: 분류 인덱서. 저장소를 열지 못하면 nil 이고, 그때 BG 작업은 바로 실패로 끝내고 다시 예약하며 계속 처리는 쓸 수 없다.
  ///   - tripPlace: 여행 장소 이름 미리 받기. 보관함 화면과 같은 인스턴스여야 빈도 제한이 이어진다.
  ///   - widgetTimeline: BG 실행이 저장소에 썼을 때(여행 교체 제외, `IndexingBackgroundResult.didChangeStore`) 끝나기 전에 한 번 위젯 갱신을 요청한다.
  ///   - taskIdentifier: 처리 작업 식별자(`TaskIdentifiers.processing`). nil 이면 등록·제출하지 않는다.
  ///   - continuedTaskIdentifier: 계속 처리 작업 식별자(`TaskIdentifiers.continued`). nil 이면 계속 처리를 쓸 수 없다.
  ///   - locale: 미리 받기 로캘. 회차를 시작할 때 한 번 읽는다.
  public convenience init(
    indexing: (any IndexingClient)?,
    tripPlace: (any TripPlaceClient)?,
    widgetTimeline: any WidgetTimelineClient,
    taskIdentifier: String?,
    continuedTaskIdentifier: String? = nil,
    locale: @escaping @Sendable () -> Locale = { .current }
  ) {
    self.init(
      indexing: indexing,
      tripPlace: tripPlace,
      widgetTimeline: widgetTimeline,
      taskIdentifier: taskIdentifier,
      continuedTaskIdentifier: continuedTaskIdentifier,
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
    continuedTaskIdentifier: String?,
    locale: @escaping @Sendable () -> Locale,
    scheduler: any BackgroundTaskScheduling,
    application: any BackgroundExecution,
    thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState,
    meterWeights: ContinuedIndexingMeter.Weights = .default
  ) {
    self.indexing = indexing
    self.tripPlace = tripPlace
    self.widgetTimeline = widgetTimeline
    self.taskIdentifier = taskIdentifier
    self.continuedTaskIdentifier = continuedTaskIdentifier
    self.locale = locale
    self.scheduler = scheduler
    self.application = application
    self.thermalState = thermalState
    self.meterWeights = meterWeights
  }

  /// BG 작업 핸들러(처리·계속 처리)를 등록한다. 앱이 실행을 마치기 전(App init)에 한 번 부른다. 식별자가 nil 이면 그 종류는 등록하지 않고,
  /// 두 번째 호출은 무시한다(같은 식별자를 두 번 등록하면 앱이 죽는다). 저장소가 없어도 등록한다(예약된 작업이 핸들러 없이 오지 않게).
  public func registerLaunchHandler() {
    guard !self.isRegistered else { return }
    self.isRegistered = true
    var isRegistered = false
    if let identifier = self.taskIdentifier {
      isRegistered = self.scheduler.register(identifier: identifier) { task in
        self.handle(task)
      }
    }
    if let identifier = self.continuedTaskIdentifier {
      self.isContinuedRegistered = self.scheduler.registerContinued(identifier: identifier) { task in
        self.handleContinued(task)
      }
    }
    #if DEBUG
      Self.logger.notice("""
      register registered=\(isRegistered ? 1 : 0, privacy: .public) \
      continued=\(self.isContinuedRegistered ? 1 : 0, privacy: .public)
      """)
    #else
      _ = isRegistered
    #endif
  }

  // MARK: - BackgroundIndexingClient

  public func appDidEnterBackground() {
    guard self.isAppActive else { return }
    self.isAppActive = false
    self.indexing?.appActivityChanged(isActive: false)
    // BG 작업(처리·계속 처리)이 도는 중이면 그 작업이 실행을 쥐고 완료 전에 저장소에서 손 뗀다.
    // 계속 처리 제출 뒤 핸들러가 아직 안 왔으면(`.pending`) 쥔 것이 없으므로 지금처럼 빌리고 제출한다.
    if self.processingTask == nil, self.continuedTask == nil {
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
    // 실행기가 BG 모드 실행을 멈추고 새 실행을 시작한다. 계속 처리 작업은 hold 를 그대로 쥐고 새 실행에 붙는다.
    self.continuedTask?.meter.runRestarted()
    // 제출했는데 핸들러가 오지 않았다. 버튼을 다시 보이게 한다(늦게 오면 그때 시작한다).
    if self.continuedPhase == .pending {
      self.continuedPhase = .idle
    }
    self.requestSettle()
  }

  // MARK: - 처리 작업

  private func handle(_ task: any BackgroundProcessingTask) {
    // 드문 중복·계속 처리 작업이 쥔 중. 도는 작업이 끝나면 필요할 때 다시 예약한다.
    guard self.processingTask == nil, self.continuedTask == nil else {
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
    self.processingTask = context
    // 앱이 뒤로 갈 때 빌린 시간이 남았으면 이제 이 작업이 실행을 쥔다.
    self.endAssertion()
    self.setExpirationHandler(task)
    self.requestSettle()
    context.work = Task { await self.runWork(indexing: indexing, context: context, signals: nil) }
    Task { await self.finish(context) }
  }

  /// 시스템이 만료 핸들러를 어느 스레드에서 부르는지 헤더가 정하지 않는다(BGTask.h). MainActor 메서드 안의 클로저는
  /// MainActor 로 추론되어 메인 밖에서 불리면 런타임 격리 확인에 걸리므로, 격리 없는 `@Sendable` 클로저로 두고
  /// Sendable 인 작업 식별만 잡아 메인으로 넘긴다.
  func setExpirationHandler(_ task: any BackgroundProcessingTask) {
    let taskID = ObjectIdentifier(task)
    task.expirationHandler = { @Sendable [weak self] in
      Task { @MainActor in self?.expireActiveTask(taskID) }
    }
  }

  /// 실행·미리 받기가 저장소에서 손 뗀 뒤에만 완료를 알린다. 순서: 손 뗌 → 위젯 갱신 요청 → 다시 예약 → 완료.
  /// 계속 처리 작업은 성공이면 실행 끝에 막대를 채우고, 뒤에서 끝나면 할 일 판정 없이 다시 예약한다(남은 소급·벡터·보강을 충전 중에 잇는다).
  func finish(_ context: TaskContext) async {
    guard let work = context.work else { return }
    let result = await work.value
    // 실행이 끝나기 전에 보낸 진행률(끝 표시 포함)을 모두 반영한 뒤 판정한다.
    await context.signalWork?.value
    let isContinued = context.kind == .continued
    // 만료(사용자 취소 포함)는 끝 도달 뒤 장소 구간에서 와도 실패다. 계속 처리는 hold 를 놓아 남은 일이 있어도 끝 도달이면 성공.
    let succeeded = !context.isExpired && (!isContinued || context.reachedFinished || !result.hasRemainingWork)
    if isContinued {
      self.continuedTask = nil
      self.continuedPhase = .finishing
      if succeeded {
        // 진행률을 하나도 받지 못하고 끝나도 0/0(불확정)이 아니라 채운 막대로 끝낸다.
        let filled = max(context.meter.completed, 1)
        context.display?.updateProgress(completed: filled, total: filled)
      }
    } else {
      self.processingTask = nil
    }
    await self.requestSettle().value
    if result.didChangeStore {
      self.widgetTimeline.reloadExpiryWidget()
    }
    // 다시 시도하려면 완료 전에 제출해야 한다(BGTask.h).
    let resubmits = isContinued
      ? context.isExpired || (result.hasRemainingWork && !context.reachedFinished) || !self.isAppActive
      : context.isExpired || result.hasRemainingWork
    if resubmits {
      self.submit()
    }
    self.logEnd(context, result)
    context.complete(success: succeeded)
    if isContinued {
      self.continuedPhase = .idle
    }
  }

  /// 만료 핸들러가 넘긴 작업이 아직 도는 작업일 때만 만료한다(끝난 작업의 늦은 만료는 버린다).
  private func expireActiveTask(_ taskID: ObjectIdentifier) {
    for context in [self.processingTask, self.continuedTask] {
      if let context, ObjectIdentifier(context.task) == taskID {
        self.expire(context)
      }
    }
  }

  /// 시스템이 작업을 끝내려 한다(계속 처리는 사용자 취소 포함). 실행을 취소하면 저장 중 배치가 끝난 뒤 돌아오고, 나머지는 `finish` 가 한다.
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
    static let logger = Logger(subsystem: "com.zopandagom.snapsort", category: "BackgroundIndexing")
  #endif
}
