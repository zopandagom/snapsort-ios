import Core
import Foundation
import Testing

struct ImageFeaturePrintTests {
  @Test("원소 수가 다르거나 유한수가 아닌 원소가 있으면 만들지 않는다")
  func rejectsInvalidValues() {
    var nan = [Float](repeating: 0, count: 768)
    nan[3] = .nan
    var infinity = [Float](repeating: 0, count: 768)
    infinity[767] = .infinity

    #expect(ImageFeaturePrint(values: [Float](repeating: 0, count: 767)) == nil)
    #expect(ImageFeaturePrint(values: [Float](repeating: 0, count: 769)) == nil)
    #expect(ImageFeaturePrint(values: nan) == nil)
    #expect(ImageFeaturePrint(values: infinity) == nil)
    #expect(ImageFeaturePrint(values: [Float](repeating: 0, count: 768)) != nil)
  }

  @Test("저장 형식으로 바꿨다 되돌리면 같은 값이고, 정렬되지 않은 Data 조각에서도 읽는다")
  func floatDataRoundTrip() throws {
    let values = (0 ..< 768).map { Float($0) * 0.001 - 0.3 }
    let original = try #require(ImageFeaturePrint(values: values))

    #expect(original.floatData.count == 768 * 4)
    #expect(ImageFeaturePrint(floatData: original.floatData) == original)

    // 앞에 한 바이트를 붙여 조각의 시작이 Float 정렬에서 어긋나게 한다.
    let unaligned = (Data([0xFF]) + original.floatData).dropFirst()
    #expect(unaligned.startIndex == 1)
    #expect(ImageFeaturePrint(floatData: unaligned) == original)
  }

  @Test("길이가 원소 수 × 4 가 아니거나 유한수가 아닌 원소면 읽지 않는다")
  func rejectsInvalidData() {
    let valid = featurePrint(1).floatData
    let nan = [Float](repeating: .nan, count: 768).withUnsafeBytes { Data($0) }

    #expect(ImageFeaturePrint(floatData: valid.dropLast()) == nil)
    #expect(ImageFeaturePrint(floatData: valid + Data([0])) == nil)
    #expect(ImageFeaturePrint(floatData: Data()) == nil)
    #expect(ImageFeaturePrint(floatData: nan) == nil)
  }

  @Test("거리는 유클리드 거리이고 자기 자신과 0, 대칭이다")
  func euclideanDistance() {
    let origin = featurePrint(0, 0)
    let point = featurePrint(3, 4)

    #expect(origin.distance(to: point) == 5)
    #expect(point.distance(to: origin) == 5)
    #expect(point.distance(to: point) == 0)
  }

  @Test("스크린샷·생성일 없음·OCR 대상은 벡터 대상이 아니다")
  func target() {
    #expect(ImageFeaturePrint.isTarget(similarAsset("photo", seconds: 0), needsTextRecognition: false))
    #expect(!ImageFeaturePrint.isTarget(
      similarAsset("shot", seconds: 0, isScreenshot: true),
      needsTextRecognition: false
    ))
    #expect(!ImageFeaturePrint.isTarget(similarAsset("undated", seconds: nil), needsTextRecognition: false))
    #expect(!ImageFeaturePrint.isTarget(similarAsset("text", seconds: 0), needsTextRecognition: true))
  }
}
