import Core
import ImageAnalysisInterface
import ImageAnalysisTesting
import Testing

struct ImageAnalysisClientFakeTests {
  @Test("정해 둔 라벨을 돌려준다")
  func returnsConfiguredLabels() async throws {
    let labels = [ImageLabel(identifier: "food", confidence: 0.8)]
    let fake = ImageAnalysisClientFake(result: .success(labels))

    #expect(try await fake.classify(.stub()) == labels)
  }

  @Test("정해 둔 실패를 던진다")
  func throwsConfiguredError() async {
    let fake = ImageAnalysisClientFake(result: .failure(.failed))

    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.classify(.stub())
    }
  }

  @Test("취소된 Task 에는 취소를 던진다")
  func throwsCancelledWhenTaskCancelled() async {
    let fake = ImageAnalysisClientFake(result: .success([ImageLabel(identifier: "food", confidence: 0.8)]))

    let task = Task { () async -> Result<[ImageLabel], ImageAnalysisError> in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        let labels = try await fake.classify(.stub())
        return .success(labels)
      } catch {
        return .failure(error)
      }
    }

    #expect(await task.value == .failure(.cancelled))
  }
}
