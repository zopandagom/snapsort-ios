import Core
import ImageAnalysisInterface
import Vision
#if DEBUG
  import os
#endif

/// Vision 기반 구현. 분류·특징 벡터는 프로세스가 쥔 세션(`VisionSessions`)으로, OCR·바코드는 요청마다 새 요청으로 한다.
public struct ImageAnalysisClientImpl: ImageAnalysisClient {
  public init() {}

  /// 모델 실행이 메인 스레드를 막지 않도록 메인 밖에서 세션 큐로 실행한다. 쓸 수 없으면(`isClassificationAvailable`) Vision 을 부르지 않는다.
  /// 큐 시한(`VisionSession.timeout`, 세대의 첫 분류는 `firstUseTimeout`)을 넘기면 큐 훅이 세대를 버리고 `.failed` 를 던진다.
  /// 줄 서 있던 큐가 버려지면 그 세대를 버리고 한 번만 새로 체크아웃해 다시 부른다(뒤면 세션이 없어 `.failed`).
  @concurrent
  public func classify(
    _ image: AnalysisImage,
    minimumConfidence: Float
  ) async throws(ImageAnalysisError) -> [ImageLabel] {
    for isRetry in [false, true] {
      if Task.isCancelled {
        throw .cancelled
      }
      let isAppActive = FeaturePrinting.availability.withLock(\.isAppActive)
      guard let lease = VisionSessions.checkout(.classify, isAppActive: isAppActive) else {
        throw Task.isCancelled ? .cancelled : .failed
      }
      let hooks = VisionWorkQueue.Hooks(
        ended: { afterTimeout in
          if afterTimeout {
            VisionSessions.stuckQueueReturned(lease)
          }
        },
        timedOut: { info in VisionSessions.timedOut(lease, info) }
      )
      let labels = try await Self.performInSession(.classify, lease: lease, isRetry: isRetry) {
        try await lease.session.classify(image, timeout: lease.timeout, hooks: hooks)
      }
      if let labels {
        return ImageClassification.labels(labels, minimumConfidence: minimumConfidence)
      }
    }
    // 다시 부른 것은 `.abandoned` 여도 실패로 끝나므로 여기에 오지 않는다.
    throw .failed
  }

  /// 큰 이미지의 OCR 은 수백 ms 가 걸리므로 메인 밖에서 실행한다.
  @concurrent
  public func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine] {
    let observations = try await Self.perform(.recognizeText) {
      try await TextRecognition.request().perform(on: image.cgImage, orientation: image.orientation)
    }
    return TextRecognition.lines(
      observations.compactMap { observation in
        // 줄마다 가장 유력한 후보 하나만 쓴다.
        observation.topCandidates(1).first.map { candidate in
          RecognizedTextLine(
            text: candidate.string,
            confidence: candidate.confidence,
            boundingBox: TextRecognition.topLeftOrigin(observation.boundingBox.cgRect)
          )
        }
      }
    )
  }

  /// 큰 이미지를 분석하므로 메인 밖에서 실행한다. 바코드 종류는 Vision 이 지원하는 전부를 찾는다(기본값).
  @concurrent
  public func detectBarcodes(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [DetectedBarcode] {
    let observations = try await Self.perform(.detectBarcodes) {
      try await DetectBarcodesRequest().perform(on: image.cgImage, orientation: image.orientation)
    }
    return BarcodeDetection.barcodes(
      observations.compactMap { observation in
        observation.payloadString.map { payload in
          DetectedBarcode(
            payload: payload,
            symbology: BarcodeDetection.symbology(observation.symbology),
            boundingBox: TextRecognition.topLeftOrigin(observation.boundingBox.cgRect)
          )
        }
      }
    )
  }

  /// 특징 벡터를 쓸 수 있는지(`FeaturePrinting.availability`). 앱이 앞에 있는 동안 시한을 넘긴 요청이 있으면 이 프로세스 동안 false,
  /// 뒤에서 넘긴 요청이 있으면 이 프로세스에서 앱이 뒤에 있을 때만 false 다. 뒤에서는 세션이 벡터에 성공한 적 있어야 한다(`VisionSessions`).
  /// 세션이 없고 돌아오지 않은 버린 큐가 상한에 닿았으면 앞에서도 false 다.
  public var isFeaturePrintAvailable: Bool {
    let (isAvailable, isAppActive) = FeaturePrinting.availability.withLock { ($0.isAvailable, $0.isAppActive) }
    return isAvailable && VisionSessions.isAvailable(.featurePrint, isAppActive: isAppActive)
  }

  /// 앞이면 대개 true, 뒤면 세션이 분류에 성공한 적 있을 때만 true 다(`VisionSessions`). 세션이 없고 돌아오지 않은 버린 큐가
  /// 상한(`VisionSessionSlot.maxStuckQueues`)에 닿았으면 앞에서도 false 다.
  public var isClassificationAvailable: Bool {
    let isAppActive = FeaturePrinting.availability.withLock(\.isAppActive)
    return VisionSessions.isAvailable(.classify, isAppActive: isAppActive)
  }

  /// 메인 밖에서 세션 큐로 실행한다. 큐 시한(`VisionSession.timeout`, 세대의 첫 벡터는 `firstUseTimeout`)은 큐에서 작업이 시작할 때부터 센다.
  /// 시한을 넘기면 부른 쪽이 기다리고 있었으면 시작 때의 ticket 으로 앞·뒤 차단을 걸고, 세대를 버리고 `.failed` 를 던진다(그 요청은 끝까지
  /// 돌 수 있고 결과는 버린다). 부른 쪽이 취소로 먼저 돌아간 뒤 남은 작업이 시한을 넘기면 차단 없이 세대만 버린다.
  /// 줄 서 있던 큐가 버려지면 그 세대를 버리고 한 번만 쓸 수 있는지 확인부터 다시 한다. 시한·기기 확인을 세션 체크아웃보다 먼저 해,
  /// 쓸 수 없는 기기(시뮬레이터)에서는 세션을 만들지 않는다. 앱이 뒤에 있으면 앞에서 불러 둔 요청으로만 만든다.
  @concurrent
  public func featurePrint(_ image: AnalysisImage) async throws(ImageAnalysisError) -> ImageFeaturePrint {
    for isRetry in [false, true] {
      if Task.isCancelled {
        throw .cancelled
      }
      let (isAvailable, ticket) = FeaturePrinting.availability.withLock { ($0.isAvailable, $0.ticket()) }
      guard isAvailable, let lease = VisionSessions.checkout(.featurePrint, isAppActive: ticket.isAppActive) else {
        throw Task.isCancelled ? .cancelled : .failed
      }
      // 큐에서 Vision 작업이 시작·끝날 때(부른 쪽이 먼저 돌아가 늦게 끝나도) 남은 뒤 요청 수를 맞춘다.
      let hooks = VisionWorkQueue.Hooks(
        started: {
          FeaturePrinting.availability.withLock { $0.requestStarted(ticket) }
        },
        ended: { afterTimeout in
          FeaturePrinting.availability.withLock { $0.requestEnded(ticket) }
          if afterTimeout {
            VisionSessions.stuckQueueReturned(lease)
          }
        },
        timedOut: { info in
          if info.isCallerWaiting {
            FeaturePrinting.availability.withLock { $0.timedOut(ticket) }
          }
          VisionSessions.timedOut(lease, info)
        }
      )
      let featurePrint = try await Self.performInSession(.featurePrint, lease: lease, isRetry: isRetry) {
        try await lease.session.featurePrint(image, timeout: lease.timeout, hooks: hooks)
      }
      if let featurePrint {
        return featurePrint
      }
    }
    // 다시 부른 것은 `.abandoned` 여도 실패로 끝나므로 여기에 오지 않는다.
    throw .failed
  }

  /// 앱 활성 상태를 프로세스 전역(`FeaturePrinting.availability`)에 둔다. 자기 잠금만 쥔다.
  public func appActivityChanged(isActive: Bool) {
    FeaturePrinting.availability.withLock { $0.appActivityChanged(isActive: isActive) }
  }

  /// Debug 로그의 `kind=`.
  private enum RequestKind: String {
    case classify
    case recognizeText
    case detectBarcodes
    case featurePrint
  }

  /// Vision 요청을 실행하고 실패를 이유로 바꾼다. 시작 전과 끝난 뒤에 Task 취소를 확인한다.
  private static func perform<Output>(
    _ kind: RequestKind,
    _ request: () async throws -> Output
  ) async throws(ImageAnalysisError) -> Output {
    if Task.isCancelled {
      throw .cancelled
    }
    let output: Output
    do {
      output = try await request()
    } catch {
      let reason = VisionFailure.analysisError(error, isTaskCancelled: Task.isCancelled)
      if reason == .failed {
        Self.logFailure(kind, error)
      }
      throw reason
    }
    // 분석 중에 취소돼도 Vision 이 결과를 돌려줄 수 있으므로 한 번 더 확인한다.
    if Task.isCancelled {
      throw .cancelled
    }
    return output
  }

  /// 세션 요청을 실행한다. 성공을 세션에 알리고, 실패는 `VisionFailure.sessionReaction` 대로 한다(취소는 실패로 보지 않는다).
  /// 버린 큐라 돌지 않았으면(처음 한 번) 그 세대를 버리고 nil 을 돌려준다(부르는 쪽이 새로 체크아웃해 다시 부른다).
  private static func performInSession<Output>(
    _ kind: RequestKind,
    lease: VisionSessions.Lease,
    isRetry: Bool,
    _ request: () async throws -> Output
  ) async throws(ImageAnalysisError) -> Output? {
    if Task.isCancelled {
      throw .cancelled
    }
    let output: Output
    do {
      output = try await request()
    } catch {
      switch VisionFailure.sessionReaction(error, isTaskCancelled: Task.isCancelled, isRetry: isRetry) {
      case .cancelled:
        throw .cancelled
      case .timedOut, .failed(discards: false):
        throw .failed
      case .retry:
        // 다시 부른 것이 옛 세대로 가지 않게 먼저 버린다(세대 검사라 시한 훅과 겹쳐도 한 번만 버린다).
        VisionSessions.discard(lease, reason: .timedOut)
        return nil
      case .failed(discards: true):
        Self.logFailure(kind, error)
        VisionSessions.discard(lease, reason: .failed)
        throw .failed
      }
    }
    VisionSessions.succeeded(lease)
    // 분석 중에 취소돼도 Vision 이 결과를 돌려줄 수 있으므로 한 번 더 확인한다.
    if Task.isCancelled {
      throw .cancelled
    }
    return output
  }

  /// Vision 실패 진단(docs/CONVENTIONS.md §4). 정수와 고정 문자열만 남기고 오류 설명·도메인은 남기지 않는다. Release 에서는 아무것도 하지 않는다.
  private static func logFailure(_ kind: RequestKind, _ error: any Error) {
    #if DEBUG
      let isVisionError = error is VisionError || (error as NSError).domain == VNErrorDomain
      self.logger.notice(
        """
        vision failed kind=\(kind.rawValue, privacy: .public) \
        code=\((error as NSError).code, privacy: .public) \
        visionError=\(isVisionError ? 1 : 0, privacy: .public)
        """
      )
    #endif
  }

  #if DEBUG
    /// 이미지 분석 Debug 로그. 세션 자리(`VisionSessions`)도 쓴다.
    static let logger = Logger(subsystem: "com.zopandagom.snapsort", category: "ImageAnalysis")
  #endif
}
