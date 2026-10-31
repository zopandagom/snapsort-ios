import Core
import Foundation
import ImageAnalysisInterface
import Testing
import Vision
@testable import ImageAnalysisImpl

/// 실제 벡터 계산(`ImageAnalysisClientImpl.featurePrint` 가 Vision 을 부르는 경로)은 자동 테스트가 없다. 시뮬레이터의 Vision 은
/// 요청이 실패하거나 멈추거나 모든 사진에 같은 벡터를 주고, Client 테스트는 호스트 앱이 없어 실기기에서 돌 수 없다(docs/CONVENTIONS.md §3).
/// 그래서 결과 변환·시뮬레이터 경로·버전 대조만 테스트한다(시한은 세션 큐 `VisionWorkQueueTests`). 전역 `FeaturePrinting.availability` 는
/// 바꾸지 않는다(같은 프로세스의 Impl 테스트끼리 나눈다). 시한 초과로 쓸 수 없게 바꾸는 판정은 `FeaturePrintAvailabilityTests` 로 본다.
/// 같은 이유로 `ImageAnalysisClientImpl.appActivityChanged` 도 부르지 않는다.
struct FeaturePrintingTests {
  private static func floatData(_ values: [Float]) -> Data {
    values.withUnsafeBytes { Data($0) }
  }

  @Test("Float 768 개면 값으로 바꾼다")
  func convertsFloatData() {
    let values = (0 ..< 768).map { Float($0) / 768 }

    let featurePrint = FeaturePrinting.featurePrint(
      data: Self.floatData(values),
      elementType: .float,
      elementCount: 768
    )

    #expect(featurePrint?.values == values)
  }

  @Test("Double 원소, 개수 다름, 데이터 길이 다름이면 nil 이다")
  func rejectsUnexpectedShape() {
    let values = [Float](repeating: 0.5, count: 768)
    let doubles = [Double](repeating: 0.5, count: 768).withUnsafeBytes { Data($0) }

    #expect(FeaturePrinting.featurePrint(data: doubles, elementType: .double, elementCount: 768) == nil)
    #expect(FeaturePrinting.featurePrint(data: Self.floatData(values), elementType: .double, elementCount: 768) == nil)
    #expect(FeaturePrinting.featurePrint(data: Self.floatData(values), elementType: .float, elementCount: 767) == nil)
    #expect(FeaturePrinting.featurePrint(
      data: Self.floatData(Array(values.dropLast())),
      elementType: .float,
      elementCount: 768
    ) == nil)
  }

  @Test("요청 revision 과 썸네일 크기가 특징 벡터 버전과 맞는다")
  func versionMatchesRequest() {
    #expect(FeaturePrinting.revision == VNGenerateImageFeaturePrintRequestRevision2)
    #expect(FeaturePrinting.revision == FeaturePrinting.revisionNumber)
    #expect(ImageFeaturePrint.version / 10000 == FeaturePrinting.revisionNumber)
    #expect(VNGenerateImageFeaturePrintRequest.supportedRevisions.contains(FeaturePrinting.revision))
  }

  @Test("시뮬레이터에서는 쓸 수 없고 Vision 을 부르지 않고 바로 실패한다", .enabled(if: !FeaturePrinting.isSupportedDevice))
  func simulatorIsUnavailable() async {
    let client = ImageAnalysisClientImpl()

    #expect(!client.isFeaturePrintAvailable)
    await #expect(throws: ImageAnalysisError.failed) { try await client.featurePrint(.stub()) }
  }

  @Test("쓸 수 없을 때 취소된 Task 면 취소를 던진다", .enabled(if: !FeaturePrinting.isSupportedDevice))
  func simulatorCancelled() async {
    let task = Task { () async -> ImageAnalysisError? in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        _ = try await ImageAnalysisClientImpl().featurePrint(.stub())
        return nil
      } catch {
        return error
      }
    }

    #expect(await task.value == .cancelled)
  }
}
