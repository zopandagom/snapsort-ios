import BackgroundIndexingInterface
import Foundation
import IndexingInterface

// 사용자가 시작한 계속 처리 작업(`BGContinuedProcessingTask`). 앞에서만 제출하고(바로 못 돌리면 실패), 핸들러가 오면 처리 작업과 같은
// `runWork` 로 분류를 쥐고 진행률을 시스템 진행 화면에 보인다. 분류·글자 읽기 끝(`isFinished`)에서 실행기 hold 만 놓고, 함께 돌던 미리 받기
// 회차가 끝나면 `finish`(손 뗌 → 위젯 → 다시 예약 → 완료)로 끝낸다. 만료·사용자 취소는 처리 작업의 만료와 같다.
// 자원은 기본이다. 뒤에서 분류·벡터는 이미지 분석이 앞에서 불러 둔 요청으로 한다(docs/ARCHITECTURE.md §4 인덱싱).

extension BackgroundIndexingClientImpl {
  /// 식별자 등록이 됐고 저장소가 있고 제출이 영구 실패하지 않았다.
  private var isContinuedSupported: Bool {
    self.isContinuedRegistered && self.indexing != nil && !self.isContinuedPermanentlyUnavailable
  }

  public var continuedIndexingState: ContinuedIndexingState {
    guard self.isContinuedSupported else { return .unsupported }
    return self.continuedPhase == .idle ? .idle : .active
  }

  public func requestContinuedIndexing(text: ContinuedIndexingText) -> ContinuedIndexingRequestResult {
    guard self.isContinuedSupported, let identifier = self.continuedTaskIdentifier else {
      Self.logSkipped("unsupported")
      return .unavailable
    }
    // 이미 제출했거나 도는 중·마무리 중이다. 같은 식별자로 다시 제출하지 않는다(연타·자동과 버튼 겹침).
    guard self.continuedPhase == .idle else {
      Self.logSkipped("busy")
      return .started
    }
    guard self.isAppActive else {
      Self.logSkipped("inactive")
      return .temporarilyUnavailable
    }
    self.continuedText = text
    let preparing = ContinuedIndexingStatus(stage: .preparing, doneCount: 0, totalCount: 0)
    do {
      try self.scheduler.submitContinued(
        identifier: identifier,
        title: text.title(preparing),
        subtitle: text.subtitle(preparing)
      )
    } catch {
      Self.logSubmitFailed(error)
      switch ContinuedSubmitFailure(error) {
      case .temporary:
        return .temporarilyUnavailable
      case .permanent:
        self.isContinuedPermanentlyUnavailable = true
        return .unavailable
      }
    }
    #if DEBUG
      Self.logger.notice("continued submit ok")
    #endif
    // 핸들러가 이미 와서 시작했으면 그 단계를 둔다.
    if self.continuedPhase == .idle {
      self.continuedPhase = .pending
    }
    return .started
  }

  // MARK: - 핸들러

  func handleContinued(_ task: any ContinuedProcessingTask) {
    // 드문 중복. 도는 작업이 끝나면 필요할 때 다시 예약한다.
    guard self.continuedTask == nil, self.continuedPhase != .running, self.continuedPhase != .finishing else {
      Self.logSkipped("handlerBusy")
      task.setTaskCompleted(success: false)
      return
    }
    // 제출이 지원 확인 뒤라 정상 흐름에서는 없다.
    guard let indexing = self.indexing, let text = self.continuedText else {
      Self.logSkipped("handlerNoText")
      self.continuedPhase = .idle
      task.setTaskCompleted(success: false)
      return
    }
    // 앞에서 제출해야만 오고 시스템이 앱을 띄우지 않으므로 화면 이벤트로 맞춘 값을 그대로 쓴다(앱 상태를 직접 읽지 않는다).
    #if DEBUG
      let thermal = self.thermalState().rawValue
      Self.logger.notice(
        "continued start active=\(self.isAppActive ? 1 : 0, privacy: .public) thermal=\(thermal, privacy: .public)"
      )
    #endif
    // 뒤에서 뜨거우면 시작하지 않고 충전 중 처리 작업으로 넘긴다. 앞이면 실행기가 양보하지 않으므로 시작한다.
    guard self.isAppActive || !Self.isHot(self.thermalState()) else {
      self.submit()
      self.continuedPhase = .idle
      task.setTaskCompleted(success: false)
      return
    }
    self.continuedPhase = .running
    // 회차는 미리 받기가 있을 때만 돈다. 그때만 회차 몫을 처음부터 전체에 넣는다.
    let context = TaskContext(
      continued: task,
      text: text,
      meterWeights: self.meterWeights,
      reservesPlaceRound: self.tripPlace != nil
    )
    self.continuedTask = context
    // 핸들러 전에 뒤로 가 빌린 시간이 남았으면 이제 이 작업이 실행을 쥔다.
    self.endAssertion()
    self.setExpirationHandler(task)
    task.updateProgress(completed: 0, total: 0)
    self.requestSettle()
    // 배치마다(2단계는 장마다, 장당 약 2초) 하나라 적고, 재시작 감지에 순서·누락 없는 값이 필요하다.
    let (signals, signalContinuation) = AsyncStream.makeStream(of: ContinuedSignal.self, bufferingPolicy: .unbounded)
    context.work = Task {
      let result = await self.runWork(indexing: indexing, context: context, signals: signalContinuation)
      signalContinuation.finish()
      return result
    }
    context.signalWork = Task {
      for await signal in signals {
        self.receive(signal, context)
      }
    }
    Task { await self.finish(context) }
  }

  // MARK: - 진행 표시

  /// 도는 계속 처리 작업의 신호만 반영한다(끝난 작업·만료한 작업의 늦은 값은 버린다).
  private func receive(_ signal: ContinuedSignal, _ context: TaskContext) {
    guard self.continuedTask === context, !context.isExpired else { return }
    #if DEBUG
      let now = ContinuousClock.now
      context.maxGap = max(context.maxGap, now - context.lastSignalAt)
      context.lastSignalAt = now
    #endif
    switch signal {
    case let .indexing(progress):
      guard !context.reachedFinished else { return }
      context.meter.receive(progress)
      if context.meter.isFinished {
        context.reachedFinished = true
        #if DEBUG
          context.finishedAt = now
        #endif
        // 실행기 hold 만 놓는다. 함께 돌던 미리 받기 회차는 끝까지 간다.
        context.indexingWork?.cancel()
        context.meter.indexingEnded()
      }
    case .placeRoundStarted:
      context.meter.placeRoundStarted()
    case let .placeProgress(progress):
      context.meter.placeProgress(progress)
    case .placeRoundEnded:
      context.meter.placeRoundEnded()
    }
    self.show(context)
  }

  /// 진행률은 받을 때마다, 제목·부제는 바뀔 때만 보낸다. 막대는 추정 시간 가중 단위이고 부제는 실제 개수다(`ContinuedIndexingMeter`).
  private func show(_ context: TaskContext) {
    guard let display = context.display else { return }
    #if DEBUG
      context.recordStage(context.meter.status?.stage, at: .now)
    #endif
    display.updateProgress(completed: context.meter.completed, total: context.meter.total)
    guard let status = context.meter.status, let text = context.text else { return }
    let title = text.title(status)
    let subtitle = text.subtitle(status)
    guard title != context.shownTitle || subtitle != context.shownSubtitle else { return }
    context.shownTitle = title
    context.shownSubtitle = subtitle
    display.updateTitle(title, subtitle: subtitle)
  }

  /// 제출 실패의 오류 코드(정수).
  private static func logSubmitFailed(_ error: any Error) {
    #if DEBUG
      logger.notice("continued submit failed code=\((error as NSError).code, privacy: .public)")
    #else
      _ = error
    #endif
  }

  /// 요청을 제출하지 않은 이유(고정 문자열).
  private static func logSkipped(_ reason: StaticString) {
    #if DEBUG
      logger.notice("continued request skipped reason=\(String(describing: reason), privacy: .public)")
    #endif
  }
}
