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

    #expect(try await fake.classify(.stub(), minimumConfidence: 0.1) == labels)
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

  @Test("정해 둔 바코드를 돌려준다")
  func returnsConfiguredBarcodes() async throws {
    let barcodes = [DetectedBarcode(
      payload: "SnapSort",
      symbology: .code128,
      boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.1)
    )]
    let fake = ImageAnalysisClientFake(detectBarcodesResult: .success(barcodes))

    #expect(try await fake.detectBarcodes(.stub()) == barcodes)
  }

  @Test("이미지마다 정한 결과를 돌려준다")
  func returnsResultPerImage() async throws {
    let fake = ImageAnalysisClientFake(
      classify: { image in
        .success([ImageLabel(identifier: image.cgImage.width == 1 ? "food" : "document", confidence: 0.8)])
      },
      recognizeText: { image in image.cgImage.width == 1 ? .failure(.failed) : .success([]) }
    )

    #expect(try await fake.classify(.stub(width: 1), minimumConfidence: 0.1).map(\.identifier) == ["food"])
    #expect(try await fake.classify(.stub(width: 2), minimumConfidence: 0.1).map(\.identifier) == ["document"])
    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.recognizeText(.stub(width: 1))
    }
    #expect(try await fake.recognizeText(.stub(width: 2)).isEmpty)
  }

  @Test("정해 둔 실패를 던진다")
  func throwsConfiguredError() async {
    let fake = ImageAnalysisClientFake(
      classifyResult: .failure(.failed),
      recognizeTextResult: .failure(.failed),
      detectBarcodesResult: .failure(.failed)
    )

    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.classify(.stub(), minimumConfidence: 0.1)
    }
    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.recognizeText(.stub())
    }
    await #expect(throws: ImageAnalysisError.failed) {
      try await fake.detectBarcodes(.stub())
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
        _ = try await fake.classify(.stub(), minimumConfidence: 0.1)
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
      do throws(ImageAnalysisError) {
        _ = try await fake.detectBarcodes(.stub())
        errors.append(nil)
      } catch {
        errors.append(error)
      }
      return errors
    }

    #expect(await task.value == [.cancelled, .cancelled, .cancelled])
  }

  @Test("기준 미만 라벨은 정해 둔 결과에서도 뺀다")
  func filtersLabelsBelowMinimumConfidence() async throws {
    let fake = ImageAnalysisClientFake(classifyResult: .success([
      ImageLabel(identifier: "food", confidence: 0.8),
      ImageLabel(identifier: "drink", confidence: 0.05),
      ImageLabel(identifier: "dog", confidence: 0.005),
    ]))

    #expect(try await fake.classify(.stub(), minimumConfidence: 0.1).map(\.identifier) == ["food"])
    #expect(try await fake.classify(.stub(), minimumConfidence: 0.01).map(\.identifier) == ["food", "drink"])
  }

  @Test("부른 순서와 기준을 기록한다")
  func recordsRequests() async throws {
    let fake = ImageAnalysisClientFake()

    _ = try await fake.classify(.stub(), minimumConfidence: 0.01)
    _ = try await fake.recognizeText(.stub())
    _ = try await fake.detectBarcodes(.stub())
    _ = try await fake.classify(.stub(), minimumConfidence: 0.1)

    #expect(fake.requests == [
      .classify(minimumConfidence: 0.01),
      .recognizeText,
      .detectBarcodes,
      .classify(minimumConfidence: 0.1),
    ])
  }

  @Test("결과를 기다리는 동안 Task 가 취소되면 결과 대신 취소를 던진다")
  func throwsCancelledWhenCancelledDuringHandler() async {
    let startedSignals = AsyncStream.makeStream(of: Void.self)
    let fake = ImageAnalysisClientFake(
      classify: { _ in
        startedSignals.continuation.yield()
        try? await Task.sleep(for: .seconds(60))
        return .success([ImageLabel(identifier: "food", confidence: 0.8)])
      },
      recognizeText: { _ in
        startedSignals.continuation.yield()
        try? await Task.sleep(for: .seconds(60))
        return .success([])
      },
      detectBarcodes: { _ in
        startedSignals.continuation.yield()
        try? await Task.sleep(for: .seconds(60))
        return .success([])
      }
    )

    var started = startedSignals.stream.makeAsyncIterator()
    for operation in [AnalysisRequest.classify(minimumConfidence: 0.1), .recognizeText, .detectBarcodes] {
      let task = Task { () async -> ImageAnalysisError? in
        do throws(ImageAnalysisError) {
          switch operation {
          case let .classify(minimumConfidence):
            _ = try await fake.classify(.stub(), minimumConfidence: minimumConfidence)
          case .recognizeText:
            _ = try await fake.recognizeText(.stub())
          case .detectBarcodes:
            _ = try await fake.detectBarcodes(.stub())
          }
          return nil
        } catch {
          return error
        }
      }
      await started.next()
      task.cancel()

      #expect(await task.value == .cancelled, "\(operation)")
    }
  }
}
