import Core
import Testing

struct CleanupSizeEstimateTests {
  private static func asset(_ width: Int, _ height: Int, screenshot: Bool) -> ImageAsset {
    ImageAsset(
      id: "a",
      creationDate: nil,
      coordinate: nil,
      pixelWidth: width,
      pixelHeight: height,
      isScreenshot: screenshot
    )
  }

  @Test("사진은 사진 계수, 스크린샷은 스크린샷 계수를 곱한다")
  func coefficients() {
    let photo = CleanupSizeEstimate.bytes(of: [Self.asset(4000, 3000, screenshot: false)])
    let screenshot = CleanupSizeEstimate.bytes(of: [Self.asset(1170, 2532, screenshot: true)])

    #expect(photo == Int64((12_000_000 * CleanupSizeEstimate.photoBytesPerPixel).rounded()))
    #expect(screenshot == Int64((1170.0 * 2532 * CleanupSizeEstimate.screenshotBytesPerPixel).rounded()))
  }

  @Test("여러 장은 합이다")
  func sums() {
    let one = Self.asset(1000, 1000, screenshot: false)
    let two = Self.asset(1000, 1000, screenshot: true)

    let total = CleanupSizeEstimate.bytes(of: [one, two])

    #expect(total == CleanupSizeEstimate.bytes(of: [one]) + CleanupSizeEstimate.bytes(of: [two]))
  }

  @Test("0 픽셀·음수 픽셀·빈 목록은 0이다")
  func zeroAndNegative() {
    #expect(CleanupSizeEstimate.bytes(of: [Self.asset(0, 3000, screenshot: false)]) == 0)
    #expect(CleanupSizeEstimate.bytes(of: [Self.asset(-5, -5, screenshot: true)]) == 0)
    #expect(CleanupSizeEstimate.bytes(of: [ImageAsset]()) == 0)
  }

  @Test("48MP 만 장도 넘치지 않는다")
  func largeValuesDoNotOverflow() {
    let assets = Array(repeating: Self.asset(8000, 6000, screenshot: true), count: 10000)

    #expect(CleanupSizeEstimate.bytes(of: assets) == 240_000_000_000)
  }
}
