import Core
import CoreGraphics
import ImageAnalysisInterface

// 1단계 바코드 확인 테스트의 준비.

/// `Fixture` 의 바코드 설정. 기본은 모든 이미지에 바코드가 없다.
struct BarcodeOptions {
  /// 읽을 수 있는 바코드가 있는 이미지.
  var found: Set<ImageAsset.ID> = []
  /// 바코드 인식에 실패하는 이미지.
  var failures: Set<ImageAsset.ID> = []
  /// 바코드를 인식할 때마다 결과 전에 부른다. 인식 도중의 일(취소)을 흉내 낸다.
  var onDetect: @Sendable (ImageAsset.ID) async -> Void = { _ in }
}

/// 바코드 Fake 가 돌려주는 내용. 저장·기록되지 않는지 확인할 때 찾는다(지어낸 값이다).
let fixtureBarcodePayload = "FIXTURE-BARCODE-0000"

extension Fixture {
  /// 바코드 Fake 의 결과. 폭으로 이미지를 찾아 `onDetect` 를 부른 뒤 `failures`·`found` 로 고른다.
  static func barcodeDetector(
    idsByWidth: [Int: ImageAsset.ID],
    options: BarcodeOptions
  ) -> @Sendable (AnalysisImage) async -> Result<[DetectedBarcode], ImageAnalysisError> {
    { image in
      let id = idsByWidth[image.cgImage.width] ?? ""
      await options.onDetect(id)
      if options.failures.contains(id) {
        return .failure(.failed)
      }
      guard options.found.contains(id) else { return .success([]) }
      return .success([DetectedBarcode(
        payload: fixtureBarcodePayload,
        symbology: .code128,
        boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
      )])
    }
  }

  /// 분석 Fake 가 받은 바코드 요청 수.
  var barcodeRequestCount: Int {
    self.analysis.requests.count { $0 == .detectBarcodes }
  }
}
