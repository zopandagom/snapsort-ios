import Core
import ImageIO
import PhotoLibraryInterface
import PhotoLibraryTesting
import Photos
import Synchronization
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PhotoLibraryImpl

struct ImageLoaderTests {
  @Test(
    "어느 요청도 iCloud 원본을 내려받지 않는다",
    arguments: [PHImageRequestOptionsDeliveryMode.highQualityFormat, .fastFormat]
  )
  func disallowsNetworkAccess(deliveryMode: PHImageRequestOptionsDeliveryMode) {
    let options = ImageLoader.requestOptions(deliveryMode: deliveryMode)

    #expect(!options.isNetworkAccessAllowed)
    #expect(options.deliveryMode == deliveryMode)
  }

  @Test("결과가 없을 때 info 로 실패 이유를 고른다")
  func mapsLoadError() {
    let cases: [(info: [AnyHashable: Any]?, expected: ImageLoadError)] = [
      ([PHImageCancelledKey: true], .cancelled),
      ([PHImageCancelledKey: true, PHImageResultIsInCloudKey: true], .cancelled),
      ([PHImageResultIsInCloudKey: true], .notAvailableLocally),
      ([PHImageResultIsInCloudKey: false], .failed),
      ([PHImageErrorKey: NSError(domain: "test", code: 1)], .failed),
      (nil, .failed),
    ]

    for testCase in cases {
      #expect(ImageLoader.loadError(info: testCase.info) == testCase.expected)
    }
  }

  @Test(
    "픽셀 수가 상한을 넘으면 비율을 지켜 상한 이하가 되는 긴 변을 고른다",
    arguments: [
      (6, 2, 12, 6),
      (8, 2, 4, 4),
      (2, 8, 4, 4),
      (1179, 20000, 4096 * 3072, 14609),
    ]
  )
  func computesMaxPixelLength(width: Int, height: Int, maxPixelCount: Int, expected: CGFloat) {
    #expect(ImageLoader.maxPixelLength(width: width, height: height, maxPixelCount: maxPixelCount) == expected)
  }

  @Test("원본 없이 요청할 크기는 상한을 지킨 긴 변이고, 픽셀 크기를 모르면 가장 큰 크기로 요청한다")
  func computesLargestTargetSize() {
    #expect(ImageLoader.largestTargetSize(width: 1179, height: 20000) == CGSize(width: 14609, height: 14609))
    #expect(ImageLoader.largestTargetSize(width: 0, height: 0) == PHImageManagerMaximumSize)
    #expect(ImageLoader.largestTargetSize(width: 0, height: 1000) == PHImageManagerMaximumSize)
  }

  @Test("상한보다 작은 이미지는 원래 크기로 디코딩한다")
  func decodesImageData() throws {
    let data = try Self.pngData(of: .stub(width: 6, height: 2))

    let image = try #require(ImageLoader.decode(data, maxPixelCount: 12))

    #expect(image.width == 6)
    #expect(image.height == 2)
  }

  @Test(
    "상한보다 큰 이미지는 비율을 지켜 픽셀 수를 상한 이하로 줄인다",
    arguments: [(8, 2, 4, 4, 1), (2, 8, 4, 1, 4), (40, 2, 20, 20, 1)]
  )
  func downsamplesLargeImage(
    width: Int,
    height: Int,
    maxPixelCount: Int,
    expectedWidth: Int,
    expectedHeight: Int
  ) throws {
    let data = try Self.pngData(of: .stub(width: width, height: height))

    let image = try #require(ImageLoader.decode(data, maxPixelCount: maxPixelCount))

    #expect(image.width == expectedWidth)
    #expect(image.height == expectedHeight)
  }

  @Test("이미지가 아닌 데이터는 디코딩하지 않는다")
  func failsToDecodeInvalidData() {
    #expect(ImageLoader.decode(Data("not an image".utf8), maxPixelCount: ImageLoader.largestPixelCount) == nil)
  }

  @Test(
    "UIImage 방향을 같은 이름의 CGImagePropertyOrientation 으로 옮긴다",
    arguments: [
      (UIImage.Orientation.up, CGImagePropertyOrientation.up),
      (.down, .down),
      (.left, .left),
      (.right, .right),
      (.upMirrored, .upMirrored),
      (.downMirrored, .downMirrored),
      (.leftMirrored, .leftMirrored),
      (.rightMirrored, .rightMirrored),
    ]
  )
  func mapsOrientation(orientation: UIImage.Orientation, expected: CGImagePropertyOrientation) {
    #expect(ImageLoader.orientation(orientation) == expected)
  }

  @Test("원하는 품질이 iCloud 에만 있으면 기기에 있는 버전으로 한 번 더 읽는다")
  func fallsBackWhenInCloud() async throws {
    var fallbackCount = 0

    let image = try await ImageLoader.fallingBackWhenInCloud { () async throws(ImageLoadError) -> AnalysisImage in
      throw .notAvailableLocally
    } to: { () async throws(ImageLoadError) -> AnalysisImage in
      fallbackCount += 1
      return .stub(width: 2, height: 2)
    }

    #expect(image.cgImage.width == 2)
    #expect(fallbackCount == 1)
  }

  @Test("원하는 품질을 읽으면 대체 요청을 하지 않는다")
  func doesNotFallBackOnSuccess() async throws {
    var fallbackCount = 0

    let image = try await ImageLoader.fallingBackWhenInCloud { () async throws(ImageLoadError) -> AnalysisImage in
      .stub(width: 4, height: 4)
    } to: { () async throws(ImageLoadError) -> AnalysisImage in
      fallbackCount += 1
      return .stub(width: 2, height: 2)
    }

    #expect(image.cgImage.width == 4)
    #expect(fallbackCount == 0)
  }

  @Test("iCloud 가 아닌 실패에는 대체 요청을 하지 않는다", arguments: [ImageLoadError.cancelled, .failed, .notFound])
  func doesNotFallBackForOtherErrors(error: ImageLoadError) async {
    var fallbackCount = 0

    await #expect(throws: error) {
      try await ImageLoader.fallingBackWhenInCloud { () async throws(ImageLoadError) -> AnalysisImage in
        throw error
      } to: { () async throws(ImageLoadError) -> AnalysisImage in
        fallbackCount += 1
        return .stub()
      }
    }
    #expect(fallbackCount == 0)
  }

  @Test("요청 결과를 그대로 돌려주고 취소하지 않는다")
  func returnsRequestResult() async {
    let cancelled = Mutex<[Int]>([])

    let result: Result<Int, ImageLoadError> = await ImageLoader.request { completion in
      completion(.success(42))
      return 1
    } cancel: { id in cancelled.withLock { $0.append(id) } }

    #expect(result == .success(42))
    #expect(cancelled.withLock { $0 }.isEmpty)
  }

  @Test("시작 전에 취소된 Task 는 요청하지 않고 취소로 끝난다")
  func skipsRequestWhenAlreadyCancelled() async {
    let startCount = Mutex(0)

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      let result: Result<Int, ImageLoadError> = await ImageLoader.request { _ in
        startCount.withLock { $0 += 1 }
        return 1
      } cancel: { _ in }
      return result
    }

    #expect(await task.value == .failure(.cancelled))
    #expect(startCount.withLock { $0 } == 0)
  }

  @Test("요청 중 취소되면 콜백을 기다리지 않고 취소로 끝나고, 요청을 취소하며, 늦게 온 콜백은 버린다")
  func cancelsInFlightRequest() async {
    let completion = Mutex<(@Sendable (Result<Int, ImageLoadError>) -> Void)?>(nil)
    let cancelled = Mutex<[Int]>([])

    let task = Task {
      let result: Result<Int, ImageLoadError> = await ImageLoader.request { callback in
        completion.withLock { $0 = callback }
        return 7
      } cancel: { id in cancelled.withLock { $0.append(id) } }
      return result
    }
    while completion.withLock({ $0 }) == nil {
      await Task.yield()
    }
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(cancelled.withLock { $0 } == [7])
    // 두 번 재개하면 CheckedContinuation 이 크래시하므로, 크래시 없이 지나가면 버린 것이다.
    completion.withLock { $0 }?(.success(1))
  }

  private static func pngData(of image: CGImage) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
  }
}
