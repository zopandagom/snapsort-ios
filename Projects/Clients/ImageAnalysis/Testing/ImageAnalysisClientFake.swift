import Core
import ImageAnalysisInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 정해 둔 결과를 돌려주고, 취소된 Task 에는 `.cancelled` 를 던진다.
/// 특징 벡터는 기본으로 쓸 수 없다(`isFeaturePrintAvailable == false`, 시뮬레이터의 Impl 과 같다). 쓸 수 없으면 결과 대신 `.failed` 를 던진다.
/// 앱 활성 알림(`appActivityChanged`)을 기록하고, 뒤에 있을 때 쓸 수 있는지를 따로 정할 수 있다(Impl 의 뒤 차단 흉내).
/// 호출한 순서와 인자를 기록해야 하므로 기록을 Mutex 로 보호하는 class 다.
public final class ImageAnalysisClientFake: ImageAnalysisClient {
  private let classifyHandler: @Sendable (AnalysisImage) async -> Result<[ImageLabel], ImageAnalysisError>
  private let recognizeTextHandler: @Sendable (AnalysisImage) async -> Result<[RecognizedTextLine], ImageAnalysisError>
  private let detectBarcodesHandler: @Sendable (AnalysisImage) async -> Result<[DetectedBarcode], ImageAnalysisError>
  private let featurePrintHandler: @Sendable (AnalysisImage) async -> Result<ImageFeaturePrint, ImageAnalysisError>
  private let featurePrintAvailability: Mutex<FakeFeaturePrintState>
  private let recordedRequests = Mutex<[AnalysisRequest]>([])

  /// 어떤 이미지든 같은 결과를 돌려준다.
  public convenience init(
    classifyResult: Result<[ImageLabel], ImageAnalysisError> = .success([]),
    recognizeTextResult: Result<[RecognizedTextLine], ImageAnalysisError> = .success([]),
    detectBarcodesResult: Result<[DetectedBarcode], ImageAnalysisError> = .success([]),
    isFeaturePrintAvailable: Bool = false,
    isFeaturePrintAvailableInBackground: Bool? = nil,
    featurePrintResult: Result<ImageFeaturePrint, ImageAnalysisError> = .failure(.failed)
  ) {
    self.init(
      classify: { _ in classifyResult },
      recognizeText: { _ in recognizeTextResult },
      detectBarcodes: { _ in detectBarcodesResult },
      isFeaturePrintAvailable: isFeaturePrintAvailable,
      isFeaturePrintAvailableInBackground: isFeaturePrintAvailableInBackground,
      featurePrint: { _ in featurePrintResult }
    )
  }

  /// 이미지마다 다른 결과를 돌려준다. 여러 이미지를 함께 다루는 테스트가 이미지 크기 등으로 결과를 고른다.
  /// 결과를 기다리게 해 분석 도중의 취소를 흉내 낼 수 있다.
  /// - Parameter isFeaturePrintAvailableInBackground: 마지막 앱 활성 알림이 false 일 때의 `isFeaturePrintAvailable`. nil 이면 앞과 같다.
  public init(
    classify: @escaping @Sendable (AnalysisImage) async -> Result<[ImageLabel], ImageAnalysisError>,
    recognizeText: @escaping @Sendable (AnalysisImage) async -> Result<[RecognizedTextLine], ImageAnalysisError>,
    detectBarcodes: @escaping @Sendable (AnalysisImage) async -> Result<[DetectedBarcode], ImageAnalysisError> = { _ in
      .success([])
    },
    isFeaturePrintAvailable: Bool = false,
    isFeaturePrintAvailableInBackground: Bool? = nil,
    featurePrint: @escaping @Sendable (AnalysisImage) async -> Result<ImageFeaturePrint, ImageAnalysisError> = { _ in
      .failure(.failed)
    }
  ) {
    self.classifyHandler = classify
    self.recognizeTextHandler = recognizeText
    self.detectBarcodesHandler = detectBarcodes
    self.featurePrintHandler = featurePrint
    self.featurePrintAvailability = Mutex(FakeFeaturePrintState(
      foreground: isFeaturePrintAvailable,
      background: isFeaturePrintAvailableInBackground ?? isFeaturePrintAvailable
    ))
  }

  /// 부른 순서대로의 요청.
  public var requests: [AnalysisRequest] {
    self.recordedRequests.withLock { $0 }
  }

  /// 실제 구현처럼 `minimumConfidence` 미만 라벨은 정해 둔 결과에서도 뺀다.
  public func classify(
    _ image: AnalysisImage,
    minimumConfidence: Float
  ) async throws(ImageAnalysisError) -> [ImageLabel] {
    self.recordedRequests.withLock { $0.append(.classify(minimumConfidence: minimumConfidence)) }
    let labels = try await Self.perform { await self.classifyHandler(image) }
    return labels.filter { $0.confidence >= minimumConfidence }
  }

  public func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine] {
    self.recordedRequests.withLock { $0.append(.recognizeText) }
    return try await Self.perform { await self.recognizeTextHandler(image) }
  }

  public func detectBarcodes(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [DetectedBarcode] {
    self.recordedRequests.withLock { $0.append(.detectBarcodes) }
    return try await Self.perform { await self.detectBarcodesHandler(image) }
  }

  public var isFeaturePrintAvailable: Bool {
    self.featurePrintAvailability.withLock(\.isAvailable)
  }

  /// `appActivityChanged(isActive:)` 에 넘긴 값을 부른 순서대로.
  public var activityChanges: [Bool] {
    self.featurePrintAvailability.withLock(\.activityChanges)
  }

  /// 이 대역을 앞·뒤 모두 쓸 수 없음으로 바꾼다. handler 가 이를 부르고 `.failed` 를 돌려주면 Impl 의 시한 초과(이후 쓸 수 없음)를 흉내 낸다.
  public func makeFeaturePrintUnavailable() {
    self.featurePrintAvailability.withLock { state in
      state.foreground = false
      state.background = false
    }
  }

  /// 기록만 한다. 자기 잠금만 쥔다(실행기가 자기 잠금 안에서 부른다).
  public func appActivityChanged(isActive: Bool) {
    self.featurePrintAvailability.withLock { $0.activityChanges.append(isActive) }
  }

  /// 쓸 수 없으면 handler 를 부르지 않고 실제 구현처럼 `.failed`(취소된 Task 면 `.cancelled`)를 던진다. 요청은 그래도 기록한다.
  public func featurePrint(_ image: AnalysisImage) async throws(ImageAnalysisError) -> ImageFeaturePrint {
    self.recordedRequests.withLock { $0.append(.featurePrint) }
    guard self.isFeaturePrintAvailable else {
      throw Task.isCancelled ? .cancelled : .failed
    }
    return try await Self.perform { await self.featurePrintHandler(image) }
  }

  /// 실제 구현처럼 결과를 받기 전과 받은 뒤에 Task 취소를 확인한다.
  private static func perform<Output>(
    _ handler: () async -> Result<Output, ImageAnalysisError>
  ) async throws(ImageAnalysisError) -> Output {
    if Task.isCancelled {
      throw .cancelled
    }
    let result = await handler()
    if Task.isCancelled {
      throw .cancelled
    }
    return try result.get()
  }
}

/// 특징 벡터를 쓸 수 있는지와 앱 활성 알림 기록.
private struct FakeFeaturePrintState {
  var foreground: Bool
  var background: Bool
  var activityChanges: [Bool] = []

  /// 마지막 알림이 false 면 뒤 값, 아니면(알림이 없으면 처음 값 true) 앞 값.
  var isAvailable: Bool {
    self.activityChanges.last == false ? self.background : self.foreground
  }
}

/// 분석 요청 한 건.
public enum AnalysisRequest: Sendable, Equatable {
  case classify(minimumConfidence: Float)
  case recognizeText
  case detectBarcodes
  case featurePrint
}
