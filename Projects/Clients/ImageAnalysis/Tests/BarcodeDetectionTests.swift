import Core
import CoreGraphics
import ImageAnalysisInterface
import Testing
import Vision
@testable import ImageAnalysisImpl

/// 실제 인식(`ImageAnalysisClientImpl.detectBarcodes` 가 Vision 을 부르는 경로)은 자동 테스트가 없다. 시뮬레이터의 Vision 은
/// 바코드 인식기를 만들지 못하고(`VisionError.operationFailed`), Client 테스트는 호스트 앱이 없어 실기기에서 돌 수 없다
/// (docs/CONVENTIONS.md §3). 그래서 결과 다듬기·종류 변환·취소만 테스트한다.
struct BarcodeDetectionTests {
  @Test("큰 바코드부터 두고, 크기가 같으면 위쪽·왼쪽을 앞에 둔다")
  func sortsByAreaThenPosition() {
    let barcodes = BarcodeDetection.barcodes([
      barcode("small", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
      barcode("large", CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2)),
      barcode("right", CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.1)),
      barcode("left", CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.1)),
    ])

    #expect(barcodes.map(\.payload) == ["large", "small", "left", "right"])
  }

  @Test("빈 내용의 바코드는 버린다")
  func dropsEmptyPayload() {
    let barcodes = BarcodeDetection.barcodes([
      barcode("", CGRect(x: 0, y: 0, width: 1, height: 1)),
      barcode("SnapSort", CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
    ])

    #expect(barcodes.map(\.payload) == ["SnapSort"])
  }

  @Test("Vision 바코드 종류를 Core 종류로 바꾼다")
  func mapsSymbology() {
    let cases: [(BarcodeSymbology, DetectedBarcode.Symbology)] = [
      (.qr, .qrCode),
      (.code128, .code128),
      (.pdf417, .pdf417),
      (.aztec, .aztec),
      (.dataMatrix, .dataMatrix),
      (.ean13, .ean13),
      (.ean8, .ean8),
      (.upce, .upce),
      (.code39, .code39),
      (.code39FullASCIIChecksum, .code39),
      (.itf14, .itf14),
      (.codabar, .other),
      (.microQR, .other),
    ]

    for (vision, expected) in cases {
      #expect(BarcodeDetection.symbology(vision) == expected, "\(vision)")
    }
  }

  @Test("취소된 Task 에서는 분석하지 않고 취소로 끝난다")
  func skipsDetectionWhenCancelled() async {
    let task = Task { () async -> Result<[DetectedBarcode], ImageAnalysisError> in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        return try await .success(ImageAnalysisClientImpl().detectBarcodes(.stub()))
      } catch {
        return .failure(error)
      }
    }

    #expect(await task.value == .failure(.cancelled))
  }
}

private func barcode(_ payload: String, _ boundingBox: CGRect) -> DetectedBarcode {
  DetectedBarcode(payload: payload, symbology: .code128, boundingBox: boundingBox)
}
