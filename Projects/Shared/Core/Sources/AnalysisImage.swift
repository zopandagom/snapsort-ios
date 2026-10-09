import CoreGraphics
import ImageIO

/// 분석(Vision 이미지 분류·OCR)에 넘기는 이미지 한 장 (docs/ARCHITECTURE.md §4).
/// 픽셀은 회전하지 않은 채로 두고 바르게 보이는 방향을 따로 담는다. Vision 의 `perform(on:orientation:)` 에 그대로 넘긴다.
/// 썸네일을 다시 인코딩하지 않도록 `Data` 가 아니라 디코딩된 `CGImage` 로 넘긴다.
public struct AnalysisImage: Sendable {
  public let cgImage: CGImage
  public let orientation: CGImagePropertyOrientation

  public init(cgImage: CGImage, orientation: CGImagePropertyOrientation) {
    self.cgImage = cgImage
    self.orientation = orientation
  }
}
