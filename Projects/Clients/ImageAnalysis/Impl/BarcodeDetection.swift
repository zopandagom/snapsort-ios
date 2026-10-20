import Core
import CoreGraphics
import Vision

/// Vision 바코드 인식 결과를 다듬는 규칙.
enum BarcodeDetection {
  /// 글자로 읽을 수 없는 바코드를 버리고 큰 것부터 둔다. 크기가 같으면 위쪽, 그다음 왼쪽을 앞에 두어 결과가 항상 같게 한다.
  /// 위치는 이미 왼쪽 위 원점으로 바꾼 값을 받는다(`TextRecognition.topLeftOrigin`).
  /// 큰 것부터 두는 이유: 기프티콘은 교환용 바코드가 가장 크고, 작은 바코드(상품 코드·QR 안내)는 뒤로 간다.
  static func barcodes(_ barcodes: [DetectedBarcode]) -> [DetectedBarcode] {
    barcodes
      .filter { !$0.payload.isEmpty }
      .sorted { lhs, rhs in
        let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
        let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
        if lhsArea != rhsArea {
          return lhsArea > rhsArea
        }
        return lhs.boundingBox.minY != rhs.boundingBox.minY
          ? lhs.boundingBox.minY < rhs.boundingBox.minY
          : lhs.boundingBox.minX < rhs.boundingBox.minX
      }
  }

  /// Vision 의 바코드 종류를 Core 의 종류로 바꾼다. 표에 없는 종류는 `other` 다.
  static func symbology(_ symbology: BarcodeSymbology) -> DetectedBarcode.Symbology {
    self.symbologies[symbology] ?? .other
  }

  private static let symbologies: [BarcodeSymbology: DetectedBarcode.Symbology] = [
    .qr: .qrCode,
    .code128: .code128,
    .pdf417: .pdf417,
    .aztec: .aztec,
    .dataMatrix: .dataMatrix,
    .ean13: .ean13,
    .ean8: .ean8,
    .upce: .upce,
    .code39: .code39,
    .code39Checksum: .code39,
    .code39FullASCII: .code39,
    .code39FullASCIIChecksum: .code39,
    .itf14: .itf14,
  ]
}
