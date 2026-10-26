import Core
import CoreGraphics
import Foundation
import PhotoStoreInterface

/// 특징 벡터·비슷한 사진 테스트의 이미지 준비. 벡터는 지어낸 값이다.
enum SimilarPhotoStoreFixture {
  static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
  static let lines = [
    RecognizedTextLine(text: "예시 문서", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)),
  ]

  /// 첫 원소만 `x` 이고 나머지는 0 인 벡터.
  static func featurePrint(_ x: Float) -> ImageFeaturePrint {
    var values = [Float](repeating: 0, count: ImageFeaturePrint.elementCount)
    values[0] = x
    return ImageFeaturePrint(values: values)!
  }

  /// 기준 시각에서 `seconds` 초 뒤에 찍은 카메라 사진(OCR 대상 아님). `x` 가 nil 이면 벡터 없이 저장한다.
  static func photo(
    _ id: String,
    seconds: TimeInterval? = 0,
    x: Float? = 0,
    isScreenshot: Bool = false,
    labels: [ImageLabel] = [ImageLabel(identifier: "food", confidence: 0.9)],
    categories: Set<ImageCategory> = [.food]
  ) -> IndexedImage {
    IndexedImage(
      asset: ImageAsset(
        id: id,
        creationDate: seconds.map { self.baseDate.addingTimeInterval($0) },
        coordinate: nil,
        pixelWidth: 4032,
        pixelHeight: 3024,
        isScreenshot: isScreenshot
      ),
      labels: labels,
      textRecognition: .notNeeded,
      categories: categories,
      featurePrint: x.map(self.featurePrint)
    )
  }

  /// OCR 대상(대기 또는 읽음) 사진. 벡터를 넘겨도 대상이 아니라 담기지 않는다.
  static func textPhoto(_ id: String, seconds: TimeInterval = 0, isRead: Bool) -> IndexedImage {
    IndexedImage(
      asset: ImageAsset(
        id: id,
        creationDate: self.baseDate.addingTimeInterval(seconds),
        coordinate: nil,
        pixelWidth: 4032,
        pixelHeight: 3024,
        isScreenshot: false
      ),
      labels: [ImageLabel(identifier: "document", confidence: 0.9)],
      textRecognition: isRead ? .recognized(self.lines) : .pending,
      categories: [.document],
      featurePrint: self.featurePrint(0)
    )
  }
}
