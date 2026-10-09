import Core
import ImageAnalysisInterface
import Vision

/// Vision 기반 구현.
public struct ImageAnalysisClientImpl: ImageAnalysisClient {
  public init() {}

  /// 모델 실행이 메인 스레드를 막지 않도록 메인 밖에서 실행한다.
  @concurrent
  public func classify(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [ImageLabel] {
    if Task.isCancelled {
      throw .cancelled
    }
    let observations: [ClassificationObservation]
    do {
      observations = try await ClassifyImageRequest().perform(on: image.cgImage, orientation: image.orientation)
    } catch {
      throw ImageClassification.analysisError(error, isTaskCancelled: Task.isCancelled)
    }
    // 분석 중에 취소돼도 Vision 이 결과를 돌려줄 수 있으므로 한 번 더 확인한다.
    if Task.isCancelled {
      throw .cancelled
    }
    return ImageClassification.labels(
      observations.map { ImageLabel(identifier: $0.identifier, confidence: $0.confidence) }
    )
  }
}
