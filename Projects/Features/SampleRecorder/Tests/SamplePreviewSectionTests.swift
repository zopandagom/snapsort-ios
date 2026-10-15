#if DEBUG
  import ImageIO
  import SwiftUI
  import Testing
  @testable import SampleRecorderFeature

  struct SamplePreviewSectionTests {
    @Test(
      "사진 방향은 같은 이름의 화면 방향으로 옮긴다",
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
    func mapsOrientation(orientation: CGImagePropertyOrientation, expected: Image.Orientation) {
      #expect(Image.Orientation(orientation) == expected)
    }
  }
#endif
