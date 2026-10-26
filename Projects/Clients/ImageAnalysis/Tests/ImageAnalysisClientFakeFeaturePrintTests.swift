import Core
import ImageAnalysisInterface
import ImageAnalysisTesting
import Testing

struct ImageAnalysisClientFakeFeaturePrintTests {
  private static let featurePrint = ImageFeaturePrint(values: Array(
    repeating: 0.5,
    count: ImageFeaturePrint.elementCount
  ))

  @Test("기본은 쓸 수 없고 결과 대신 실패를 던지며 요청은 기록한다")
  func unavailableByDefault() async throws {
    let featurePrint = try #require(Self.featurePrint)
    let fake = ImageAnalysisClientFake(featurePrintResult: .success(featurePrint))

    #expect(!fake.isFeaturePrintAvailable)
    await #expect(throws: ImageAnalysisError.failed) { try await fake.featurePrint(.stub()) }
    #expect(fake.requests == [.featurePrint])
  }

  @Test("쓸 수 있으면 정해 둔 벡터를 돌려준다")
  func returnsConfiguredFeaturePrint() async throws {
    let featurePrint = try #require(Self.featurePrint)
    let fake = ImageAnalysisClientFake(isFeaturePrintAvailable: true, featurePrintResult: .success(featurePrint))

    #expect(try await fake.featurePrint(.stub()) == featurePrint)
    #expect(fake.requests == [.featurePrint])
  }

  @Test("쓸 수 없게 바꾸면 그 뒤 요청은 handler 를 부르지 않고 실패한다")
  func becomesUnavailable() async throws {
    let featurePrint = try #require(Self.featurePrint)
    let fake = ImageAnalysisClientFake(isFeaturePrintAvailable: true, featurePrintResult: .success(featurePrint))

    fake.makeFeaturePrintUnavailable()

    #expect(!fake.isFeaturePrintAvailable)
    await #expect(throws: ImageAnalysisError.failed) { try await fake.featurePrint(.stub()) }
  }

  @Test("쓸 수 없을 때 취소된 Task 면 취소를 던진다")
  func unavailableCancelled() async {
    let fake = ImageAnalysisClientFake()
    let task = Task { () async -> ImageAnalysisError? in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        _ = try await fake.featurePrint(.stub())
        return nil
      } catch {
        return error
      }
    }

    #expect(await task.value == .cancelled)
  }
}
