import Core
import ImageAnalysisInterface

/// 1단계 바코드 확인 (docs/ARCHITECTURE.md §4 분류 3단 파이프라인·인덱싱).
/// 라벨로는 OCR 대상이 아닌 위치 없는 이미지(저장한 기프티콘이 음식 라벨로만 잡히는 경우)를 바코드로 한 번 더 본다.
/// 바코드 내용은 보지도 저장·로그하지도 않는다 (docs/CONVENTIONS.md §4).
extension IndexingRun {
  /// 확인 대상(`TextRecognitionPolicy.needsBarcodeCheck`)이면 분류와 같은 썸네일로 인식해 읽을 수 있는 바코드가 있는지만 돌려준다.
  /// 대체 버전 썸네일도 그대로 쓴다(작아서 못 읽으면 바코드 없음과 같다). 실패는 바코드 없음(false)으로 보고 분류를 이어 가고, 취소면 던진다.
  func phaseOneHasBarcode(
    asset: ImageAsset,
    labels: [ImageLabel],
    thumbnail: AnalysisImage
  ) async throws(IndexingStop) -> Bool {
    guard TextRecognitionPolicy.needsBarcodeCheck(asset: asset, labels: labels) else { return false }
    do throws(ImageAnalysisError) {
      // 있는지만 보고 결과는 버린다.
      return try await !self.imageAnalysis.detectBarcodes(thumbnail).isEmpty
    } catch {
      switch error {
      case .cancelled: throw .cancelled
      case .failed: return false
      }
    }
  }
}
