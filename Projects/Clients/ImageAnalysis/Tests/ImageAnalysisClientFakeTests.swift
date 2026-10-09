import Core
import CoreGraphics
import ImageAnalysisInterface
import ImageAnalysisTesting
import Testing

struct ImageAnalysisClientFakeTests {
  @Test("정해 둔 라벨을 돌려준다")
  func returnsConfiguredLabels() async throws {
    let labels = [ImageLabel(identifier: "food", confidence: 0.8)]
    let fake = ImageAnalysisClientFake(classifyResult: .success(labels))

    #expect(try await fake.classify(.stub()) == labels)
  }

  @Test("정해 둔 텍스트를 돌려준다")
  func returnsConfiguredText() async throws {
    let lines = [RecognizedTextLine(
      text: "유효기간",
      confidence: 0.9,
      boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)
    )]
    let fake = ImageAnalysisClientFake(recognizeTextResult: .success(lines))

    #expect(try await fake.recognizeText(.stub()) == lines)
  }

  @Test("정해 둔 실패를 던진다")
  func throwsConfiguredError() async {
    let fake = ImageAnalysisClientFake(classifyResult: .failure(.failed), recognizeTextResult: .failure(.failed))

    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.classify(.stub())
    }
    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.recognizeText(.stub())
    }
  }

  @Test("취소된 Task 에는 취소를 던진다")
  func throwsCancelledWhenTaskCancelled() async {
    let fake = ImageAnalysisClientFake(
      classifyResult: .success([ImageLabel(identifier: "food", confidence: 0.8)]),
      recognizeTextResult: .success([RecognizedTextLine(text: "SnapSort", confidence: 0.9, boundingBox: .zero)])
    )

    let task = Task { () async -> [ImageAnalysisError?] in
      withUnsafeCurrentTask { $0?.cancel() }
      var errors: [ImageAnalysisError?] = []
      do throws(ImageAnalysisError) {
        _ = try await fake.classify(.stub())
        errors.append(nil)
      } catch {
        errors.append(error)
      }
      do throws(ImageAnalysisError) {
        _ = try await fake.recognizeText(.stub())
        errors.append(nil)
      } catch {
        errors.append(error)
      }
      return errors
    }

    #expect(await task.value == [.cancelled, .cancelled])
  }
}
