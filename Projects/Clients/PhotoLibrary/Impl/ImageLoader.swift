import Core
import ImageIO
import PhotoLibraryInterface
import Photos
import Synchronization
import UIKit

/// PHImageManager 로 분석용 이미지를 읽는다. 어느 요청도 iCloud 원본을 내려받지 않는다.
/// PHImageManager 는 결과를 메인 스레드로 줄 수 있으므로, 콜백에서는 값만 옮기고 디코딩은 호출한 쪽 실행자에서 한다.
enum ImageLoader {
  /// 분류용 썸네일의 긴 변(픽셀). 임시 값이고, 정확도·1만 장 측정 작업에서 확정한다.
  static let thumbnailLength: CGFloat = 512

  /// OCR·바코드용 이미지의 픽셀 수 상한(약 12.6MP). 48MP 원본을 그대로 디코딩하면 한 장에 약 190MB 라 줄인다 (이 상한이면 약 50MB).
  /// 긴 변이 아니라 픽셀 수로 제한해, 스크롤 캡처·긴 영수증처럼 세로로 긴 이미지도 폭이 지나치게 줄지 않게 한다.
  /// 영수증의 작은 글자를 읽을 수 있는 크기로 둔 임시 값이고, 정확도·1만 장 측정 작업에서 확정한다.
  static let largestPixelCount = 4096 * 3072

  /// 맞는 크기의 캐시가 있으면 PhotoKit 이 그것을 쓰고, 없으면 원본에서 줄일 수 있다. `.highQualityFormat` 이라 결과는 한 번만 온다.
  static func thumbnail(of asset: PHAsset) async throws(ImageLoadError) -> AnalysisImage {
    let targetSize = CGSize(width: self.thumbnailLength, height: self.thumbnailLength)
    return try await self.fallingBackWhenInCloud {
      () async throws(ImageLoadError) -> AnalysisImage in
      try await self.requestImage(of: asset, targetSize: targetSize, deliveryMode: .highQualityFormat)
    } to: { () async throws(ImageLoadError) -> AnalysisImage in
      try await self.requestImage(of: asset, targetSize: targetSize, deliveryMode: .fastFormat)
    }
  }

  /// 원본 데이터가 기기에 있으면 픽셀 수를 `largestPixelCount` 이하로 줄여 디코딩한다. 원본이 iCloud 에만 있으면 기기에서 바로 줄 수 있는 버전으로 대신한다.
  /// `.fastFormat` 이라 기기에 더 큰 버전이 있어도 작은 버전이 올 수 있다.
  static func largestAvailable(of asset: PHAsset) async throws(ImageLoadError) -> AnalysisImage {
    try await self.fallingBackWhenInCloud { () async throws(ImageLoadError) -> AnalysisImage in
      let (data, orientation) = try await self.requestImageData(of: asset)
      guard let cgImage = self.decode(data, maxPixelCount: self.largestPixelCount) else { throw .failed }
      return AnalysisImage(cgImage: cgImage, orientation: orientation)
    } to: { () async throws(ImageLoadError) -> AnalysisImage in
      let targetSize = self.largestTargetSize(width: asset.pixelWidth, height: asset.pixelHeight)
      return try await self.requestImage(of: asset, targetSize: targetSize, deliveryMode: .fastFormat)
    }
  }

  // MARK: - 테스트할 규칙

  /// 원하는 품질이 iCloud 에만 있으면 기기에 있는 버전을 바로 주는 요청으로 한 번 더 읽는다. 다른 실패는 그대로 던진다.
  static func fallingBackWhenInCloud(
    _ primary: () async throws(ImageLoadError) -> AnalysisImage,
    to fallback: () async throws(ImageLoadError) -> AnalysisImage
  ) async throws(ImageLoadError) -> AnalysisImage {
    do {
      return try await primary()
    } catch .notAvailableLocally {
      return try await fallback()
    }
  }

  /// `.fastFormat` 은 기기에 있는 버전 중 바로 줄 수 있는 것을 한 번만 준다.
  static func requestOptions(deliveryMode: PHImageRequestOptionsDeliveryMode) -> PHImageRequestOptions {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = false
    options.deliveryMode = deliveryMode
    options.resizeMode = .fast
    options.version = .current
    return options
  }

  /// 결과가 없을 때 info 로 이유를 고른다. 취소가 iCloud 여부보다 우선한다.
  static func loadError(info: [AnyHashable: Any]?) -> ImageLoadError {
    if info?[PHImageCancelledKey] as? Bool == true {
      return .cancelled
    }
    if info?[PHImageResultIsInCloudKey] as? Bool == true {
      return .notAvailableLocally
    }
    return .failed
  }

  /// 픽셀 수가 `maxPixelCount` 이하가 되도록 비율을 지켜 줄였을 때의 긴 변. 이미 작으면 원래 긴 변이다.
  static func maxPixelLength(width: Int, height: Int, maxPixelCount: Int) -> CGFloat {
    let longSide = CGFloat(max(width, height))
    let pixelCount = width * height
    guard pixelCount > maxPixelCount else { return longSide }
    return (longSide * (CGFloat(maxPixelCount) / CGFloat(pixelCount)).squareRoot()).rounded(.down)
  }

  /// 원본 데이터 없이 요청할 때의 크기. 픽셀 수 상한을 지킨 긴 변의 정사각형이고, `.aspectFit` 으로 비율을 지킨다.
  /// 에셋의 픽셀 크기를 모르면(0) 0 크기로 요청하지 않도록 `PHImageManagerMaximumSize` 를 쓴다.
  static func largestTargetSize(width: Int, height: Int) -> CGSize {
    guard width > 0, height > 0 else { return PHImageManagerMaximumSize }
    let length = self.maxPixelLength(width: width, height: height, maxPixelCount: self.largestPixelCount)
    return CGSize(width: length, height: length)
  }

  /// 주 이미지를 픽셀 수가 `maxPixelCount` 이하가 되게 줄여 지금 디코딩해 둔다. 더 작은 이미지는 키우지 않는다.
  /// 원본 크기로 디코딩한 뒤 줄이지 않고 디코딩하면서 줄여 메모리를 아낀다. 그대로 두면 Vision 이 처음 픽셀을 읽을 때 디코딩한다.
  /// 방향은 적용하지 않는다 (`AnalysisImage` 가 따로 담는다). HEIC 처럼 이미지가 여러 장 든 파일은 주 이미지가 0번이 아닐 수 있다.
  static func decode(_ data: Data, maxPixelCount: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let index = CGImageSourceGetPrimaryImageIndex(source)
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: self.maxPixelLength(
        width: width,
        height: height,
        maxPixelCount: maxPixelCount
      ),
      kCGImageSourceShouldCacheImmediately: true,
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, index, options)
  }

  static func orientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: .up
    case .down: .down
    case .left: .left
    case .right: .right
    case .upMirrored: .upMirrored
    case .downMirrored: .downMirrored
    case .leftMirrored: .leftMirrored
    case .rightMirrored: .rightMirrored
    @unknown default: .up
    }
  }

  /// 콜백 요청 하나를 async 로 바꾸고, Task 가 취소되면 요청도 취소한다.
  /// 결과는 콜백과 취소 중 먼저 온 쪽으로 한 번만 정한다. 취소된 요청의 콜백을 PhotoKit 이 부르지 않아도 멈추지 않고, 늦게 온 콜백은 버린다.
  /// 시작하기 전에 이미 취소됐으면 요청하지 않는다.
  static func request<Value: Sendable, RequestID: Sendable>(
    start: (@escaping @Sendable (Result<Value, ImageLoadError>) -> Void) -> RequestID,
    cancel: @escaping @Sendable (RequestID) -> Void
  ) async -> Result<Value, ImageLoadError> {
    let pending = PendingRequest<Value, RequestID>()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard pending.wait(with: continuation) else { return }
        let id = start { pending.finish($0) }
        if !pending.register(id) {
          cancel(id)
        }
      }
    } onCancel: {
      if let id = pending.cancel() {
        cancel(id)
      }
    }
  }

  // MARK: - Private

  private static func requestImage(
    of asset: PHAsset,
    targetSize: CGSize,
    deliveryMode: PHImageRequestOptionsDeliveryMode
  ) async throws(ImageLoadError) -> AnalysisImage {
    let options = self.requestOptions(deliveryMode: deliveryMode)
    let result: Result<AnalysisImage, ImageLoadError> = await self.request { completion in
      PHImageManager.default().requestImage(
        for: asset,
        targetSize: targetSize,
        contentMode: .aspectFit,
        options: options
      ) { image, info in
        guard let image, let cgImage = image.cgImage else {
          completion(.failure(self.loadError(info: info)))
          return
        }
        completion(.success(AnalysisImage(cgImage: cgImage, orientation: self.orientation(image.imageOrientation))))
      }
    } cancel: { PHImageManager.default().cancelImageRequest($0) }
    return try result.get()
  }

  private static func requestImageData(
    of asset: PHAsset
  ) async throws(ImageLoadError) -> (Data, CGImagePropertyOrientation) {
    let options = self.requestOptions(deliveryMode: .highQualityFormat)
    let result: Result<(Data, CGImagePropertyOrientation), ImageLoadError> = await self.request { completion in
      PHImageManager.default()
        .requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, info in
          completion(data.map { .success(($0, orientation)) } ?? .failure(self.loadError(info: info)))
        }
    } cancel: { PHImageManager.default().cancelImageRequest($0) }
    return try result.get()
  }
}

/// 콜백과 취소 중 먼저 온 쪽으로 continuation 을 한 번만 재개한다. 둘은 다른 스레드에서 올 수 있어 Mutex 로 보호한다.
private final class PendingRequest<Value: Sendable, RequestID: Sendable>: Sendable {
  private struct State {
    var continuation: CheckedContinuation<Result<Value, ImageLoadError>, Never>?
    var requestID: RequestID?
    var isCancelled = false
  }

  private let state = Mutex(State())

  /// 재개할 continuation 을 맡긴다. 이미 취소됐으면 바로 `.cancelled` 로 재개하고 false.
  func wait(with continuation: CheckedContinuation<Result<Value, ImageLoadError>, Never>) -> Bool {
    let isCancelled = self.state.withLock { state in
      if !state.isCancelled {
        state.continuation = continuation
      }
      return state.isCancelled
    }
    if isCancelled {
      continuation.resume(returning: .failure(.cancelled))
    }
    return !isCancelled
  }

  /// 시작한 요청의 식별자를 기록한다. 그사이 취소됐으면 false 이고, 부른 쪽이 요청을 취소한다.
  func register(_ requestID: RequestID) -> Bool {
    self.state.withLock { state in
      state.requestID = requestID
      return !state.isCancelled
    }
  }

  func finish(_ result: Result<Value, ImageLoadError>) {
    self.takeContinuation()?.resume(returning: result)
  }

  /// `.cancelled` 로 재개하고, 이미 시작한 요청이 있으면 그 식별자를 돌려준다.
  func cancel() -> RequestID? {
    let (continuation, requestID) = self.state.withLock { state in
      state.isCancelled = true
      defer { state.continuation = nil }
      return (state.continuation, state.requestID)
    }
    continuation?.resume(returning: .failure(.cancelled))
    return requestID
  }

  private func takeContinuation() -> CheckedContinuation<Result<Value, ImageLoadError>, Never>? {
    self.state.withLock { state in
      defer { state.continuation = nil }
      return state.continuation
    }
  }
}
