import Core
import Foundation

/// 테스트와 Example 앱에서 쓰는 이미지. 확인할 값만 바꿔 쓰고 나머지는 촬영 사진 기본값을 둔다.
public extension ImageAsset {
  static func stub(
    id: String,
    creationDate: Date? = nil,
    coordinate: Coordinate? = nil,
    pixelWidth: Int = 4032,
    pixelHeight: Int = 3024,
    isScreenshot: Bool = false
  ) -> ImageAsset {
    ImageAsset(
      id: id,
      creationDate: creationDate,
      coordinate: coordinate,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      isScreenshot: isScreenshot
    )
  }
}

public extension [ImageAsset] {
  /// `image-0`, `image-1` … 식별자를 가진 이미지 `count` 장.
  static func stubs(count: Int) -> [ImageAsset] {
    (0 ..< count).map { .stub(id: "image-\($0)") }
  }
}
