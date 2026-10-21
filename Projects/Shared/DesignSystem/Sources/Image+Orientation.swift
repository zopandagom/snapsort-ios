import ImageIO
import SwiftUI

public extension Image.Orientation {
  /// 같은 이름의 방향으로 바꾼다. 원시 값은 서로 다르므로(예: `.right` 는 6 과 7) rawValue 로 바꾸지 않는다.
  init(_ orientation: CGImagePropertyOrientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}

public extension Image {
  /// 회전하지 않은 픽셀과 바르게 보이는 방향으로 그린다 (Core `AnalysisImage` 의 두 값). 다시 인코딩하지 않고 scale 1 로 그린다.
  init(decorative cgImage: CGImage, orientation: CGImagePropertyOrientation) {
    self.init(decorative: cgImage, scale: 1, orientation: Image.Orientation(orientation))
  }
}
