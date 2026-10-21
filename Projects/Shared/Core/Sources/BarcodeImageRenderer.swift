import CoreGraphics
import CoreImage
import ImageIO

/// 화면에 크게 보일 바코드 이미지 (docs/ARCHITECTURE.md §4 캡처 정보 추출).
/// 바코드를 그린 것이라 내용을 담고 있으므로 기기 밖으로 보내거나 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct BarcodeImage: Sendable, Hashable {
  public let cgImage: CGImage
  /// 화면이 `Image(decorative:orientation:)` 로 돌릴 방향. 다시 그린 것은 `.up`, 자른 것은 원본 방향 그대로다.
  public let orientation: CGImagePropertyOrientation
  /// Core Image 로 다시 그렸으면 true(화면이 `.interpolation(.none)` 으로 확대한다), 원본 영역을 자른 것이면 false.
  public let isRedrawn: Bool

  public init(cgImage: CGImage, orientation: CGImagePropertyOrientation, isRedrawn: Bool) {
    self.cgImage = cgImage
    self.orientation = orientation
    self.isRedrawn = isRedrawn
  }
}

/// 읽은 바코드를 크게 보일 이미지로 만든다 (docs/ARCHITECTURE.md §4 캡처 정보 추출).
/// Core Image 생성기로 다시 그리면 원본의 흐림·기울어짐 없이 스캐너가 읽기 쉽다. 다시 그리면 내용이 달라지는 경우
/// (Code128 은 비 ASCII 를 그리지 못하고, PDF417·Aztec 은 UTF-8 을 다른 글자로 읽힌다)와 생성기가 없는 종류는
/// 원본에서 바코드 영역을 잘라 확대한다.
public enum BarcodeImageRenderer {
  /// 자를 때 바코드 위치 사방에 더하는 여백(위치 크기에 대한 비율). 스캐너가 가장자리를 찾게 한다.
  static let cropMarginRatio: CGFloat = 0.1

  /// 생성기는 스레드 안전이라 하나를 함께 쓴다.
  private static let context = CIContext()

  /// 다시 그릴 수 있으면(`canRedraw`) Core Image 생성기로 그린다(확대는 화면이 `.interpolation(.none)` 으로).
  /// 아니면 원본에서 바코드 영역(정규화 위치에 사방 10% 여백, 이미지 안으로 자름)을 잘라 원본 방향 그대로 돌려준다.
  /// 자른 영역은 `CGContext` 로 그 크기의 새 비트맵에 다시 그려 독립 버퍼로 돌려준다(`CGImage.cropping(to:)` 는 원본 픽셀 버퍼를
  /// 공유해 원본 전체를 붙잡는다). 방향은 원본 그대로 두고 화면이 `Image(decorative:orientation:)` 로 돌린다.
  /// 그리기·자르기에 실패하면(위치가 이미지 밖이면) nil.
  public static func image(for barcode: DetectedBarcode, in source: AnalysisImage) -> BarcodeImage? {
    if self.canRedraw(barcode), let redrawn = self.redrawn(barcode) {
      return BarcodeImage(cgImage: redrawn, orientation: .up, isRedrawn: true)
    }
    return self.cropped(barcode, in: source).map {
      BarcodeImage(cgImage: $0, orientation: source.orientation, isRedrawn: false)
    }
  }

  /// QR·Code128·PDF417·Aztec 이고 내용의 모든 유니코드 스칼라가 0x00…0x7F.
  static func canRedraw(_ barcode: DetectedBarcode) -> Bool {
    guard self.generatorName(barcode.symbology) != nil, !barcode.payload.isEmpty else {
      return false
    }
    return barcode.payload.unicodeScalars.allSatisfy(\.isASCII)
  }

  /// 바르게 돌린 기준 정규화 위치(원점 왼쪽 위) → 원본 CGImage 픽셀 사각형(원점 왼쪽 위, `cropping(to:)` 좌표).
  /// 방향 8가지는 EXIF 정의(0번째 행·열이 바르게 본 화면의 어느 쪽인지)를 따른다. 이미지 안으로 자르고 정수 픽셀로 넓힌다.
  /// 이미지와 겹치지 않으면 빈 사각형(`isEmpty`).
  static func pixelRect(
    for normalized: CGRect,
    imageWidth: Int,
    imageHeight: Int,
    orientation: CGImagePropertyOrientation
  ) -> CGRect {
    let x = normalized.minX
    let y = normalized.minY
    let width = normalized.width
    let height = normalized.height
    let raw = switch orientation {
    case .up:
      CGRect(x: x, y: y, width: width, height: height)
    case .upMirrored:
      CGRect(x: 1 - x - width, y: y, width: width, height: height)
    case .down:
      CGRect(x: 1 - x - width, y: 1 - y - height, width: width, height: height)
    case .downMirrored:
      CGRect(x: x, y: 1 - y - height, width: width, height: height)
    case .leftMirrored:
      CGRect(x: y, y: x, width: height, height: width)
    case .right:
      CGRect(x: y, y: 1 - x - width, width: height, height: width)
    case .rightMirrored:
      CGRect(x: 1 - y - height, y: 1 - x - width, width: height, height: width)
    case .left:
      CGRect(x: 1 - y - height, y: x, width: height, height: width)
    @unknown default:
      CGRect(x: x, y: y, width: width, height: height)
    }
    // `1 - x - width` 같은 계산의 부동소수 오차(3.9999…)로 한 픽셀 넓어지지 않게 정수에 아주 가까운 가장자리는 그 정수로 본다.
    func snapped(_ value: CGFloat) -> CGFloat {
      let rounded = value.rounded()
      return abs(value - rounded) < 1e-6 ? rounded : value
    }
    let minX = snapped(raw.minX * CGFloat(imageWidth)).rounded(.down)
    let minY = snapped(raw.minY * CGFloat(imageHeight)).rounded(.down)
    let maxX = snapped(raw.maxX * CGFloat(imageWidth)).rounded(.up)
    let maxY = snapped(raw.maxY * CGFloat(imageHeight)).rounded(.up)
    let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
    let clipped = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bounds)
    return clipped.isNull ? .zero : clipped
  }

  private static func generatorName(_ symbology: DetectedBarcode.Symbology) -> String? {
    switch symbology {
    case .qrCode: "CIQRCodeGenerator"
    case .code128: "CICode128BarcodeGenerator"
    case .pdf417: "CIPDF417BarcodeGenerator"
    case .aztec: "CIAztecCodeGenerator"
    case .dataMatrix, .ean13, .ean8, .upce, .code39, .itf14, .other: nil
    }
  }

  /// 생성기가 내용을 그리지 못하면 nil.
  private static func redrawn(_ barcode: DetectedBarcode) -> CGImage? {
    guard let name = self.generatorName(barcode.symbology),
          let message = barcode.payload.data(using: .ascii),
          let filter = CIFilter(name: name)
    else {
      return nil
    }
    filter.setValue(message, forKey: "inputMessage")
    if barcode.symbology == .qrCode {
      filter.setValue("M", forKey: "inputCorrectionLevel")
    }
    guard let output = filter.outputImage, !output.extent.isInfinite, !output.extent.isEmpty else {
      return nil
    }
    return self.context.createCGImage(output, from: output.extent)
  }

  /// 원본에서 바코드 영역을 잘라 새 비트맵에 그린 것.
  private static func cropped(_ barcode: DetectedBarcode, in source: AnalysisImage) -> CGImage? {
    let box = barcode.boundingBox
    let padded = box.insetBy(dx: -box.width * self.cropMarginRatio, dy: -box.height * self.cropMarginRatio)
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !padded.isNull, !padded.isEmpty else {
      return nil
    }
    let rect = self.pixelRect(
      for: padded,
      imageWidth: source.cgImage.width,
      imageHeight: source.cgImage.height,
      orientation: source.orientation
    )
    guard !rect.isEmpty, let region = source.cgImage.cropping(to: rect),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: region.width,
            height: region.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
      return nil
    }
    context.draw(region, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
    return context.makeImage()
  }
}
