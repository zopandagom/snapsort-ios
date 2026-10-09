import Core
import ImageAnalysisInterface

/// 테스트와 Example 앱용 대역. 어떤 이미지든 정해 둔 결과를 돌려주고, 취소된 Task 에는 `.cancelled` 를 던진다.
public struct ImageAnalysisClientFake: ImageAnalysisClient {
  public let result: Result<[ImageLabel], ImageAnalysisError>

  public init(result: Result<[ImageLabel], ImageAnalysisError> = .success([])) {
    self.result = result
  }

  public func classify(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [ImageLabel] {
    if Task.isCancelled {
      throw .cancelled
    }
    return try self.result.get()
  }
}
