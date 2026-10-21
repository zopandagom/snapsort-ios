import DesignSystem
import ImageIO
import SwiftUI
import Testing

struct ImageOrientationTests {
  @Test(
    "CGImagePropertyOrientation 을 같은 이름의 SwiftUI 방향으로 바꾼다",
    arguments: [
      (CGImagePropertyOrientation.up, Image.Orientation.up),
      (.upMirrored, .upMirrored),
      (.down, .down),
      (.downMirrored, .downMirrored),
      (.left, .left),
      (.leftMirrored, .leftMirrored),
      (.right, .right),
      (.rightMirrored, .rightMirrored),
    ]
  )
  func mapsEveryOrientationByName(orientation: CGImagePropertyOrientation, expected: Image.Orientation) {
    #expect(Image.Orientation(orientation) == expected)
  }
}
