import Core
import CoreGraphics
import ImageIO

/// 테스트와 Example 앱에서 쓰는 분석 이미지. 크기와 방향만 정하고 픽셀은 한 색으로 채운다.
public extension AnalysisImage {
  static func stub(width: Int = 4, height: Int = 3, orientation: CGImagePropertyOrientation = .up) -> AnalysisImage {
    AnalysisImage(cgImage: .stub(width: width, height: height), orientation: orientation)
  }
}

public extension CGImage {
  /// 한 색으로 채운 RGBA 이미지.
  static func stub(width: Int, height: Int) -> CGImage {
    // 고정 크기 비트맵 생성은 메모리 부족이 아니면 실패하지 않는다. 실패하면 테스트 설정이 잘못된 것이다.
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { preconditionFailure("비트맵 컨텍스트를 만들 수 없음: \(width)x\(height)") }
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { preconditionFailure("이미지를 만들 수 없음: \(width)x\(height)") }
    return image
  }
}
