import Core
import ImageAnalysisInterface
import Vision

/// Vision 기반 구현.
public struct ImageAnalysisClientImpl: ImageAnalysisClient {
  public init() {}

  /// 모델 실행이 메인 스레드를 막지 않도록 메인 밖에서 실행한다.
  @concurrent
  public func classify(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [ImageLabel] {
    let observations = try await Self.perform {
      try await ClassifyImageRequest().perform(on: image.cgImage, orientation: image.orientation)
    }
    return ImageClassification.labels(
      observations.map { ImageLabel(identifier: $0.identifier, confidence: $0.confidence) }
    )
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
