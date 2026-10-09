import Core
import CoreGraphics

extension AnalysisImage {
  /// 한 색으로 채운 분석 이미지. PhotoLibraryTesting 의 같은 이름 대역은 다른 Client 라 쓰지 않는다.
  static func stub(width: Int = 4, height: Int = 3) -> AnalysisImage {
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
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { preconditionFailure("이미지를 만들 수 없음: \(width)x\(height)") }
    return AnalysisImage(cgImage: image, orientation: .up)
  }
}
