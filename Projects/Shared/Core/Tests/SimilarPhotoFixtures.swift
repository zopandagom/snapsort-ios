import Core
import Foundation

// 비슷한 사진 묶기 테스트가 함께 쓰는 값. 벡터는 지어낸 값이다.

/// 묶기 테스트의 기준 시각.
let similarPhotoBaseDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// 앞 원소 몇 개만 정하고 나머지는 0 인 벡터. 원소 하나만 다르면 두 벡터의 거리는 그 차이다.
func featurePrint(_ leading: Float...) -> ImageFeaturePrint {
  var values = [Float](repeating: 0, count: ImageFeaturePrint.elementCount)
  for (index, value) in leading.enumerated() {
    values[index] = value
  }
  return ImageFeaturePrint(values: values)!
}

/// 기준 시각에서 `seconds` 초 뒤에 찍은 카메라 사진.
func similarAsset(
  _ id: String,
  seconds: TimeInterval?,
  width: Int = 4032,
  height: Int = 3024,
  isScreenshot: Bool = false
) -> ImageAsset {
  ImageAsset(
    id: id,
    creationDate: seconds.map { similarPhotoBaseDate.addingTimeInterval($0) },
    coordinate: nil,
    pixelWidth: width,
    pixelHeight: height,
    isScreenshot: isScreenshot
  )
}

/// 벡터 첫 원소가 `x` 인 사진.
func similarPhoto(
  _ id: String,
  seconds: TimeInterval?,
  x: Float = 0,
  width: Int = 4032,
  height: Int = 3024,
  isScreenshot: Bool = false
) -> FeaturePrintedPhoto {
  FeaturePrintedPhoto(
    asset: similarAsset(id, seconds: seconds, width: width, height: height, isScreenshot: isScreenshot),
    featurePrint: featurePrint(x)
  )
}
