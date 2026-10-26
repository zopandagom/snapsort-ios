import Accelerate
import Foundation

/// 비슷한 사진 비교용 이미지 특징 벡터 (docs/ARCHITECTURE.md §4 정리 도우미·저장소). 사진에서 만든 값이라 로그에 남기지 않는다.
public struct ImageFeaturePrint: Sendable, Hashable {
  /// Vision `GenerateImageFeaturePrintRequest` revision 2 의 원소 수.
  public static let elementCount = 768
  /// 저장한 벡터가 지금 계산과 비교 가능한지 가르는 버전: 요청 revision × 10_000 + 썸네일 요청 긴 변(px).
  /// 요청(revision·`cropAndScaleAction` 등 설정)이나 썸네일 요청 긴 변(PhotoLibrary `ImageLoader.thumbnailLength`)을 바꾸면 올린다
  /// (저장된 벡터를 인덱서가 다시 계산한다). 두 Impl 테스트가 이 값의 두 부분을 자기 상수와 대조한다.
  /// 썸네일은 빠른 크기 조정(`.fast`)으로 읽어 실제 크기가 요청과 다를 수 있다. 크기가 달라지면 거리가 커져 묶이지 않는 쪽이다.
  public static let version = 2 * 10000 + 512

  /// 원소 `elementCount` 개, 모두 유한수.
  public let values: [Float]

  /// 개수가 `elementCount` 가 아니거나 유한수가 아닌 원소가 있으면 nil.
  public init?(values: [Float]) {
    guard values.count == Self.elementCount, values.allSatisfy(\.isFinite) else {
      return nil
    }
    self.values = values
  }

  /// 기기 바이트 순서의 Float 원소를 이어 붙인 값(Vision `data`, 저장 형식). 길이가 `elementCount * 4` 가 아니면 nil.
  public init?(floatData: Data) {
    let stride = MemoryLayout<Float>.stride
    guard floatData.count == Self.elementCount * stride else {
      return nil
    }
    // Data 버퍼는 Float 정렬이 보장되지 않으므로 메모리를 다시 해석하지 않고 바이트를 복사한다.
    let values = [Float](unsafeUninitializedCapacity: Self.elementCount) { buffer, initializedCount in
      let copied = floatData.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
      initializedCount = copied / stride
    }
    self.init(values: values)
  }

  /// 기기 바이트 순서의 Float 원소를 이어 붙인 값. `init?(floatData:)` 와 짝이다.
  public var floatData: Data {
    self.values.withUnsafeBytes { Data($0) }
  }

  /// 유클리드 거리(제곱근). Vision `distance(to:)` 는 거리의 제곱이라 쓰지 않는다(docs/ARCHITECTURE.md §4 정리 도우미 실측).
  /// 정리 화면이 묶을 때마다 이웃마다 두 번 부르므로 vDSP 로 계산한다(Mac -O 1만 장 묶기: 반복문 5.5~8.9ms, vDSP 2.4~2.6ms).
  public func distance(to other: ImageFeaturePrint) -> Float {
    var sum: Float = 0
    vDSP_distancesq(self.values, 1, other.values, 1, &sum, vDSP_Length(Self.elementCount))
    return sum.squareRoot()
  }

  /// 벡터를 만들 대상: 스크린샷이 아니고 생성일이 있고 OCR 대상이 아닌 사진.
  /// 글자가 많은 사진(문서·영수증·책 쪽 촬영)은 연속 쪽 촬영이 거리상 거의 같아 다른 쪽이 기본 선택되는 오묶음이 되므로 뺀다.
  public static func isTarget(_ asset: ImageAsset, needsTextRecognition: Bool) -> Bool {
    !asset.isScreenshot && asset.creationDate != nil && !needsTextRecognition
  }
}
