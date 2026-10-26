/// 지우면 확보될 저장 공간 추정 (docs/ARCHITECTURE.md §4 정리 도우미). 파일 크기를 읽지 않고 픽셀 수 × 계수로 셈한다.
public enum CleanupSizeEstimate {
  /// 바이트/픽셀. 임시값: HEIC 사진(12MP 약 2~3MB)의 흔한 크기에서 잡았다.
  /// 실기기에서 설정 > 일반 > iPhone 저장 공간 > 사진 의 변화로 조정한다(PR 본문에 기록).
  public static let photoBytesPerPixel = 0.2
  /// 바이트/픽셀. 임시값: PNG 스크린샷(약 3MP 1~2MB)의 흔한 크기에서 잡았다. 조정 방법은 `photoBytesPerPixel` 과 같다.
  public static let screenshotBytesPerPixel = 0.5

  /// 각 이미지 `pixelWidth * pixelHeight * 계수(스크린샷이면 screenshot)` 를 더한 바이트(반올림). 음수·0 픽셀은 0.
  public static func bytes(of assets: some Sequence<ImageAsset>) -> Int64 {
    let total = assets.reduce(0.0) { sum, asset in
      let pixels = Double(max(asset.pixelWidth, 0)) * Double(max(asset.pixelHeight, 0))
      return sum + pixels * (asset.isScreenshot ? self.screenshotBytesPerPixel : self.photoBytesPerPixel)
    }
    return Int64(total.rounded())
  }
}
