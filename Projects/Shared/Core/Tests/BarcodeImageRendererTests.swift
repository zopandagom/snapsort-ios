import CoreGraphics
import CoreImage
import ImageIO
import Testing
@testable import Core

/// 바코드 내용은 지어낸 값이다 (docs/CONVENTIONS.md §3).
struct BarcodeImageRendererTests {
  @Test(
    "QR·Code128·PDF417·Aztec 이고 내용이 ASCII 일 때만 다시 그린다",
    arguments: [
      (DetectedBarcode.Symbology.qrCode, "1234567890123", true),
      (.code128, "AB-12 x", true),
      (.pdf417, "1234567890123", true),
      (.aztec, "1234567890123", true),
      (.code128, "\u{1D}0101", true),
      (.qrCode, "가나다123", false),
      (.code128, "é12", false),
      (.pdf417, "가나다123", false),
      (.aztec, "가나다123", false),
      (.qrCode, "", false),
      (.ean13, "8801234567893", false),
      (.dataMatrix, "1234567890123", false),
      (.other, "1234567890123", false),
    ]
  )
  func decidesRedraw(symbology: DetectedBarcode.Symbology, payload: String, expected: Bool) {
    #expect(BarcodeImageRenderer.canRedraw(Self.barcode(symbology, payload)) == expected)
  }

  @Test("네 종류 ASCII 바코드는 Core Image 로 다시 그린다", arguments: [
    DetectedBarcode.Symbology.qrCode, .code128, .pdf417, .aztec,
  ])
  func redrawsASCII(symbology: DetectedBarcode.Symbology) throws {
    let source = try Self.source(width: 200, height: 100, orientation: .right)

    let image = try #require(BarcodeImageRenderer.image(for: Self.barcode(symbology, "1234567890123"), in: source))

    #expect(image.isRedrawn)
    #expect(image.orientation == .up)
    #expect(image.cgImage.width > 0)
    #expect(image.cgImage.height > 0)
  }

  @Test("다시 그릴 수 없으면 원본 영역에 여백을 더해 원본 방향 그대로 자른다")
  func cropsWhenRedrawIsNotPossible() throws {
    let source = try Self.source(width: 100, height: 100, orientation: .left)
    let barcode = Self.barcode(.code128, "가나다123", box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))

    let image = try #require(BarcodeImageRenderer.image(for: barcode, in: source))

    #expect(!image.isRedrawn)
    #expect(image.orientation == .left)
    // 사방 10% 여백: 0.38…0.62 → 24×24 픽셀.
    #expect(image.cgImage.width == 24)
    #expect(image.cgImage.height == 24)
  }

  @Test("자른 이미지는 원본 버퍼를 붙잡지 않는 새 비트맵이다")
  func croppedImageIsIndependentBuffer() throws {
    let source = try Self.source(width: 100, height: 60, orientation: .up)
    let barcode = Self.barcode(.other, "1234", box: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))

    let image = try #require(BarcodeImageRenderer.image(for: barcode, in: source))

    #expect(image.cgImage.width < source.cgImage.width)
    #expect(image.cgImage.height < source.cgImage.height)
    #expect(image.cgImage.dataProvider !== source.cgImage.dataProvider)
    #expect(image.cgImage.bytesPerRow < source.cgImage.bytesPerRow)
  }

  @Test("위치가 이미지 밖이면 nil 이다")
  func returnsNilOutsideImage() throws {
    let source = try Self.source(width: 100, height: 100, orientation: .up)
    let barcode = Self.barcode(.other, "1234", box: CGRect(x: 1.5, y: 0.2, width: 0.2, height: 0.2))

    #expect(BarcodeImageRenderer.image(for: barcode, in: source) == nil)
    #expect(BarcodeImageRenderer.pixelRect(
      for: barcode.boundingBox,
      imageWidth: 100,
      imageHeight: 100,
      orientation: .up
    ).isEmpty)
  }

  @Test("이미지 가장자리를 넘는 위치는 이미지 안으로 자른다")
  func clipsToImageBounds() {
    let rect = BarcodeImageRenderer.pixelRect(
      for: CGRect(x: 0.9, y: -0.1, width: 0.3, height: 0.3),
      imageWidth: 100,
      imageHeight: 50,
      orientation: .up
    )

    #expect(rect == CGRect(x: 90, y: 0, width: 10, height: 10))
  }

  /// 원본 픽셀의 비대칭 위치에 칠한 칸을 Core Image 로 바르게 돌린 뒤 찾은 정규화 위치를 `pixelRect` 로 되돌리면 원래 칸이 나온다.
  /// 방향 정의를 손으로 옮긴 기대값이 아니라 Core Image 의 EXIF 방향 처리와 대조한다.
  @Test("정규화 위치를 원본 픽셀 사각형으로 바꾼다(방향 8가지)", arguments: [
    CGImagePropertyOrientation.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored,
  ])
  func convertsNormalizedRectForEveryOrientation(orientation: CGImagePropertyOrientation) throws {
    let raw = CGRect(x: 4, y: 2, width: 8, height: 6)
    let source = try Self.marked(width: 40, height: 20, marked: raw)
    let oriented = CIImage(cgImage: source).oriented(orientation)
    let displayed = try #require(CIContext().createCGImage(oriented, from: oriented.extent))
    let marked = try #require(Self.markedRect(in: displayed))
    let normalized = CGRect(
      x: marked.minX / CGFloat(displayed.width),
      y: marked.minY / CGFloat(displayed.height),
      width: marked.width / CGFloat(displayed.width),
      height: marked.height / CGFloat(displayed.height)
    )

    let rect = BarcodeImageRenderer.pixelRect(
      for: normalized,
      imageWidth: 40,
      imageHeight: 20,
      orientation: orientation
    )

    #expect(rect == raw)
  }

  private static func barcode(
    _ symbology: DetectedBarcode.Symbology,
    _ payload: String,
    box: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.3)
  ) -> DetectedBarcode {
    DetectedBarcode(payload: payload, symbology: symbology, boundingBox: box)
  }

  private static func source(
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation
  ) throws -> AnalysisImage {
    try AnalysisImage(
      cgImage: self.marked(width: width, height: height, marked: .zero),
      orientation: orientation
    )
  }

  /// 흰 바탕에 `marked`(원점 왼쪽 위 픽셀 좌표) 칸만 검게 칠한 이미지.
  private static func marked(width: Int, height: Int, marked: CGRect) throws -> CGImage {
    let context = try #require(self.context(width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    // CGContext 는 원점이 왼쪽 아래라 위아래를 뒤집어 칠한다.
    context.fill(CGRect(x: marked.minX, y: CGFloat(height) - marked.maxY, width: marked.width, height: marked.height))
    return try #require(context.makeImage())
  }

  /// 검은 픽셀을 모두 감싸는 사각형(원점 왼쪽 위 픽셀 좌표).
  private static func markedRect(in image: CGImage) -> CGRect? {
    let width = image.width
    let height = image.height
    guard let context = self.context(width: width, height: height) else {
      return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
      return nil
    }
    var rect: CGRect?
    for row in 0 ..< height {
      for column in 0 ..< width where data[row * context.bytesPerRow + column * 4] < 128 {
        let pixel = CGRect(x: column, y: row, width: 1, height: 1)
        rect = rect.map { $0.union(pixel) } ?? pixel
      }
    }
    return rect
  }

  private static func context(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }
}
