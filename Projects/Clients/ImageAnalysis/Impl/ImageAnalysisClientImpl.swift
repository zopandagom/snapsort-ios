import Core
import ImageAnalysisInterface
import Vision

/// Vision 기반 구현.
public struct ImageAnalysisClientImpl: ImageAnalysisClient {
  public init() {}

  /// 모델 실행이 메인 스레드를 막지 않도록 메인 밖에서 실행한다.
  @concurrent
  public func classify(
    _ image: AnalysisImage,
    minimumConfidence: Float
  ) async throws(ImageAnalysisError) -> [ImageLabel] {
    let observations = try await Self.perform {
      try await ClassifyImageRequest().perform(on: image.cgImage, orientation: image.orientation)
    }
    return ImageClassification.labels(
      observations.map { ImageLabel(identifier: $0.identifier, confidence: $0.confidence) },
      minimumConfidence: minimumConfidence
    )
  }

  /// 큰 이미지의 OCR 은 수백 ms 가 걸리므로 메인 밖에서 실행한다.
  @concurrent
  public func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine] {
    let observations = try await Self.perform {
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
    let observations = try await Self.perform {
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
  /// 뒤에서 넘긴 요청이 있으면 이 프로세스에서 앱이 뒤에 있을 때만 false 다.
  public var isFeaturePrintAvailable: Bool {
    FeaturePrinting.availability.withLock(\.isAvailable)
  }

  /// 메인 밖에서 시한(`FeaturePrinting.timeout`)과 경주시켜 실행한다. 시한을 넘기면 시작 때의 ticket 으로 앞·뒤 차단을 걸고 `.failed` 를 던진다
  /// (그 요청은 끝까지 돌 수 있고 결과는 버린다). 앱이 뒤에 있을 때 시작한 요청은 CPU 로 계산한다(`FeaturePrinting.pinToCPU`).
  /// `cropAndScaleAction` 은 기본값(`.scaleToFill`)을 둔다.
  @concurrent
  public func featurePrint(_ image: AnalysisImage) async throws(ImageAnalysisError) -> ImageFeaturePrint {
    let (isAvailable, ticket) = FeaturePrinting.availability.withLock { ($0.isAvailable, $0.ticket()) }
    guard isAvailable else {
      throw Task.isCancelled ? .cancelled : .failed
    }
    let outcome = try await FeaturePrinting
      .race(timeout: FeaturePrinting.timeout) { () async throws(ImageAnalysisError) in
        // Vision 작업이 돌아올 때(경주가 먼저 끝나 늦게 돌아와도) 남은 뒤 요청 수를 맞춘다.
        FeaturePrinting.availability.withLock { $0.requestStarted(ticket) }
        defer { FeaturePrinting.availability.withLock { $0.requestEnded(ticket) } }
        let observation = try await Self.perform {
          var request = GenerateImageFeaturePrintRequest(FeaturePrinting.revision)
          if !ticket.isAppActive {
            FeaturePrinting.pinToCPU(&request)
          }
          return try await request.perform(on: image.cgImage, orientation: image.orientation)
        }
        guard let featurePrint = FeaturePrinting.featurePrint(
          data: observation.data,
          elementType: observation.elementType,
          elementCount: observation.elementCount
        ) else {
          throw .failed
        }
        return featurePrint
      }
    let handled = FeaturePrinting.handle(outcome)
    if handled.makesUnavailable {
      FeaturePrinting.availability.withLock { $0.timedOut(ticket) }
    }
    return try handled.result.get()
  }

  /// 앱 활성 상태를 프로세스 전역(`FeaturePrinting.availability`)에 둔다. 자기 잠금만 쥔다.
  public func appActivityChanged(isActive: Bool) {
    FeaturePrinting.availability.withLock { $0.appActivityChanged(isActive: isActive) }
  }

  /// Vision 요청을 실행하고 실패를 이유로 바꾼다. 시작 전과 끝난 뒤에 Task 취소를 확인한다.
  private static func perform<Output>(
    _ request: () async throws -> Output
  ) async throws(ImageAnalysisError) -> Output {
    if Task.isCancelled {
      throw .cancelled
    }
    let output: Output
    do {
      output = try await request()
    } catch {
      throw VisionFailure.analysisError(error, isTaskCancelled: Task.isCancelled)
    }
    // 분석 중에 취소돼도 Vision 이 결과를 돌려줄 수 있으므로 한 번 더 확인한다.
    if Task.isCancelled {
      throw .cancelled
    }
    return output
  }
}
