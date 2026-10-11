import Core
import ImageAnalysisInterface

/// 테스트와 Example 앱용 대역. 정해 둔 결과를 돌려주고, 취소된 Task 에는 `.cancelled` 를 던진다.
public struct ImageAnalysisClientFake: ImageAnalysisClient {
  private let classifyHandler: @Sendable (AnalysisImage) -> Result<[ImageLabel], ImageAnalysisError>
  private let recognizeTextHandler: @Sendable (AnalysisImage) -> Result<[RecognizedTextLine], ImageAnalysisError>

  /// 어떤 이미지든 같은 결과를 돌려준다.
  public init(
    classifyResult: Result<[ImageLabel], ImageAnalysisError> = .success([]),
    recognizeTextResult: Result<[RecognizedTextLine], ImageAnalysisError> = .success([])
  ) {
    self.init(classify: { _ in classifyResult }, recognizeText: { _ in recognizeTextResult })
  }

  /// 이미지마다 다른 결과를 돌려준다. 여러 이미지를 함께 다루는 테스트가 이미지 크기 등으로 결과를 고른다.
  public init(
    classify: @escaping @Sendable (AnalysisImage) -> Result<[ImageLabel], ImageAnalysisError>,
    recognizeText: @escaping @Sendable (AnalysisImage) -> Result<[RecognizedTextLine], ImageAnalysisError>
  ) {
    self.classifyHandler = classify
    self.recognizeTextHandler = recognizeText
  }

  public func classify(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [ImageLabel] {
    if Task.isCancelled {
      throw .cancelled
    }
    return try self.classifyHandler(image).get()
  }

  public func recognizeText(_ image: AnalysisImage) async throws(ImageAnalysisError) -> [RecognizedTextLine] {
    if Task.isCancelled {
      throw .cancelled
    }
    return try self.recognizeTextHandler(image).get()
  }
}
