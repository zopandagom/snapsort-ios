import Core
import ImageAnalysisInterface

/// 테스트와 Example 앱용 대역. 어떤 이미지든 정해 둔 결과를 돌려주고, 취소된 Task 에는 `.cancelled` 를 던진다.
public struct ImageAnalysisClientFake: ImageAnalysisClient {
  public let classifyResult: Result<[ImageLabel], ImageAnalysisError>
  public let recognizeTextResult: Result<[RecognizedTextLine], ImageAnalysisError>

  public init(
    classifyResult: Result<[ImageLabel], ImageAnalysisError> = .success([]),
    recognizeTextResult: Result<[RecognizedTextLine], ImageAnalysisError> = .success([])
  ) {
    self.classifyResult = classifyResult
    self.recognizeTextResult = recognizeTextResult
  }

  public func classify(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [ImageLabel] {
    if Task.isCancelled {
      throw .cancelled
    }
    return try self.classifyResult.get()
  }

  public func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine] {
    if Task.isCancelled {
      throw .cancelled
    }
    return try self.recognizeTextResult.get()
  }
}
