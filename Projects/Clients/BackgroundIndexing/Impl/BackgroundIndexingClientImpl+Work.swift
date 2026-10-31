import Foundation
import IndexingInterface
import Synchronization
import TripPlaceInterface

// MARK: - 실행

extension BackgroundIndexingClientImpl {
  /// 분류를 쥐고, 1단계를 마친 진행률이 오면 미리 받기 회차를 한 번 돌린다. 분류가 먼저 끝나도 회차는 끝까지 간다.
  /// 분류 hold 는 따로 된 `indexingWork` 로 쥐어 `context.indexingWork` 에 둔다: 이것만 취소하면 hold 만 놓고 회차는 그대로 가고,
  /// 이 실행(`context.work`)을 취소하면 둘 다 멈춘다. 첫 await 전에 대입해 hold 직후 온 진행률도 놓기를 놓치지 않는다.
  /// 계속 처리 작업(`signals` 있음)은 진행률·회차 진행을 신호로 넘기고, 회차 1 이 시작하지 못했으면(진행 알림 없음) 분류 쪽이 끝난 뒤
  /// 분류·글자 읽기를 마쳤고 앱이 뒤일 때 회차를 한 번 더 연다(보관함 화면 회차가 돌던 중 홈으로 나간 경우).
  func runWork(
    indexing: any IndexingClient,
    context: TaskContext,
    signals: AsyncStream<ContinuedSignal>.Continuation?
  ) async -> IndexingBackgroundResult {
    let (classified, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let thermalState = self.thermalState
    let tripPlace = self.tripPlace
    let locale = self.locale
    let contextID = ObjectIdentifier(context)
    // 분류·글자 읽기 끝을 받았는지. 조정자 상태(신호 소비를 거쳐 늦을 수 있음) 대신 회차 2 판정에 같이 쓴다.
    let sawFinished = ReportFlag()
    let indexingWork = Task {
      await indexing.runInBackground(
        shouldYield: { Self.isHot(thermalState()) },
        progress: { progress in
          signals?.yield(.indexing(progress))
          if progress.isFinished {
            sawFinished.set()
          }
          if progress.phase != .classifying {
            continuation.yield()
          }
        }
      )
    }
    context.indexingWork = indexingWork
    return await withTaskGroup(of: IndexingBackgroundResult?.self) { group in
      group.addTask {
        let result = await withTaskCancellationHandler {
          await indexingWork.value
        } onCancel: {
          indexingWork.cancel()
        }
        continuation.finish()
        return result
      }
      group.addTask {
        guard let tripPlace else { return nil }
        await self.runPlaceRounds(
          classified: classified,
          tripPlace: tripPlace,
          locale: locale,
          signals: signals,
          secondRoundAllowed: { await self.allowsSecondRound(contextID, sawFinished: sawFinished.isSet) }
        )
        return nil
      }
      var result: IndexingBackgroundResult?
      for await value in group {
        result = value ?? result
      }
      // 분류 쪽은 늘 값을 돌려준다. 혹시 없으면 남은 것으로 보고 다시 예약한다.
      return result ?? IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false)
    }
  }

  /// 1단계를 마친 첫 진행률에 회차 1 을 돌린다. 계속 처리 작업이면 분류 쪽이 끝날 때까지(`classified` 닫힘) 기다린 뒤
  /// 회차 1 이 진행을 알리지 않았고 취소되지 않았고 `secondRoundAllowed` 가 참이면 회차 2 를 한 번 돌린다.
  private nonisolated func runPlaceRounds(
    classified: AsyncStream<Void>,
    tripPlace: any TripPlaceClient,
    locale: @escaping @Sendable () -> Locale,
    signals: AsyncStream<ContinuedSignal>.Continuation?,
    secondRoundAllowed: @Sendable () async -> Bool
  ) async {
    var iterator = classified.makeAsyncIterator()
    guard await iterator.next() != nil else { return }
    let didReport = await Self.prefetchRound(tripPlace, locale: locale(), signals: signals)
    guard signals != nil else { return }
    while await iterator.next() != nil {}
    guard !didReport, !Task.isCancelled, await secondRoundAllowed() else { return }
    _ = await Self.prefetchRound(tripPlace, locale: locale(), signals: signals)
  }

  /// 미리 받기 회차 하나. 계속 처리 작업이면 시작·진행·끝을 신호로 넘긴다(처리 작업은 진행을 받지 않는다). 진행 알림이 있었으면 true.
  private nonisolated static func prefetchRound(
    _ tripPlace: any TripPlaceClient,
    locale: Locale,
    signals: AsyncStream<ContinuedSignal>.Continuation?
  ) async -> Bool {
    guard let signals else {
      await tripPlace.prefetchPlaces(locale: locale)
      return false
    }
    let didReport = ReportFlag()
    signals.yield(.placeRoundStarted)
    await tripPlace.prefetchPlaces(locale: locale) { progress in
      didReport.set()
      signals.yield(.placeProgress(progress))
    }
    signals.yield(.placeRoundEnded)
    return didReport.isSet
  }

  /// 회차 2 조건 중 조정자 상태: 그 계속 처리 작업이 분류·글자 읽기를 마쳤고 앱이 뒤에 있다(앞이면 보관함 화면 회차가 한다).
  private func allowsSecondRound(_ contextID: ObjectIdentifier, sawFinished: Bool) -> Bool {
    guard let context = self.continuedTask, ObjectIdentifier(context) == contextID else { return false }
    return (sawFinished || context.reachedFinished) && !self.isAppActive
  }
}

/// 회차가 진행을 알렸는지. 회차를 도는 actor 안에서 세우고 회차가 끝난 뒤 읽는다.
private final class ReportFlag: Sendable {
  private let value = Mutex(false)

  var isSet: Bool {
    self.value.withLock { $0 }
  }

  func set() {
    self.value.withLock { $0 = true }
  }
}

// MARK: - 저장소 출입 맞추기·실행 시간·제출

extension BackgroundIndexingClientImpl {
  /// 앱이 앞에 있거나 BG 작업(처리·계속 처리)이 실행을 쥐면 저장소를 쓴다.
  private var isStoreAllowed: Bool {
    self.isAppActive || self.processingTask != nil || self.continuedTask != nil
  }

  @discardableResult
  func requestSettle() -> Task<Void, Never> {
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

  func beginAssertion() {
    let previous = self.assertion
    self.assertion = self.application.begin(name: Self.pauseAssertionName) {
      self.endAssertion()
    }
    if let previous {
      self.application.end(previous)
    }
  }

  /// 빌린 시간을 한 번만 돌려준다(만료 핸들러와 맞추기가 겹쳐도).
  func endAssertion() {
    guard let assertion = self.assertion else { return }
    self.assertion = nil
    self.application.end(assertion)
  }

  /// 충전 중에만, 네트워크 조건 없이 요청한다(오프라인 충전 밤에도 분류. 미리 받기는 네트워크가 있으면 되는 최선 노력).
  func submit() {
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

  /// 작업 끝의 Debug 수치 로그. 정수·고정 문자열만 남긴다(문구·식별자 없음). 처리 작업은 기존 `end` 줄,
  /// 계속 처리는 `continued meter`(단위·단계 시간)·`continued end` 줄.
  func logEnd(_ context: TaskContext, _ result: IndexingBackgroundResult) {
    #if DEBUG
      let now = ContinuousClock.now
      let seconds = Int((now - context.startedAt).components.seconds)
      guard context.kind == .continued else {
        Self.logger.notice("""
        end remaining=\(result.hasRemainingWork ? 1 : 0, privacy: .public) \
        changed=\(result.didChangeStore ? 1 : 0, privacy: .public) \
        expired=\(context.isExpired ? 1 : 0, privacy: .public) seconds=\(seconds, privacy: .public)
        """)
        return
      }
      let tailSeconds = context.finishedAt.map { Int((now - $0).components.seconds) } ?? 0
      // 단계별 초 ÷ 장·키 수로 단위 무게를 다시 정할 근거(겹치는 장소 회차는 보인 단계에 든다).
      context.recordStage(nil, at: now)
      let meter = context.meter
      Self.logger.notice("""
      continued meter units=\(meter.completed, privacy: .public) total=\(meter.total, privacy: .public) \
      classified=\(meter.classifiedCount, privacy: .public) texts=\(meter.textCount, privacy: .public) \
      places=\(meter.placeDone, privacy: .public) \
      textSharePermille=\(Int((meter.textShare * 1000).rounded()), privacy: .public) \
      classifySeconds=\(Int(context.classifyDuration.components.seconds), privacy: .public) \
      textSeconds=\(Int(context.textDuration.components.seconds), privacy: .public) \
      placeSeconds=\(Int(context.placeDuration.components.seconds), privacy: .public)
      """)
      Self.logger.notice("""
      continued end reached=\(context.reachedFinished ? 1 : 0, privacy: .public) \
      remaining=\(result.hasRemainingWork ? 1 : 0, privacy: .public) \
      changed=\(result.didChangeStore ? 1 : 0, privacy: .public) \
      expired=\(context.isExpired ? 1 : 0, privacy: .public) seconds=\(seconds, privacy: .public) \
      maxGap=\(Int(context.maxGap.components.seconds), privacy: .public) \
      placeRounds=\(context.meter.endedRounds, privacy: .public) \
      placeKeys=\(context.meter.placeDone, privacy: .public) tailSeconds=\(tailSeconds, privacy: .public)
      """)
    #else
      _ = (context, result)
    #endif
  }
}
