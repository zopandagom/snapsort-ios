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

  /// PhotoKit 이 캐시해 둔 썸네일을 쓰므로 원본을 디코딩하지 않는다. `.highQualityFormat` 이라 결과는 한 번만 온다.
  static func thumbnail(of asset: PHAsset) async throws(ImageLoadError) -> AnalysisImage {
    let targetSize = CGSize(width: self.thumbnailLength, height: self.thumbnailLength)
    return try await self.fallingBackWhenInCloud {
      () async throws(ImageLoadError) -> AnalysisImage in
      try await self.requestImage(of: asset, targetSize: targetSize, deliveryMode: .highQualityFormat)
    } to: { () async throws(ImageLoadError) -> AnalysisImage in
      try await self.requestImage(of: asset, targetSize: targetSize, deliveryMode: .fastFormat)
    }
  }

  /// 원본 데이터가 기기에 있으면 그것을 디코딩한다. 원본이 iCloud 에만 있으면 기기에 남은 가장 큰 버전으로 대신한다.
  static func largestAvailable(of asset: PHAsset) async throws(ImageLoadError) -> AnalysisImage {
    try await self.fallingBackWhenInCloud { () async throws(ImageLoadError) -> AnalysisImage in
      let (data, orientation) = try await self.requestImageData(of: asset)
      guard let cgImage = self.decode(data) else { throw .failed }
      return AnalysisImage(cgImage: cgImage, orientation: orientation)
    } to: { () async throws(ImageLoadError) -> AnalysisImage in
      try await self.requestImage(of: asset, targetSize: PHImageManagerMaximumSize, deliveryMode: .fastFormat)
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

  /// 주 이미지를 지금 디코딩해 둔다. 그대로 두면 Vision 이 처음 픽셀을 읽을 때 디코딩한다.
  /// HEIC 처럼 이미지가 여러 장 든 파일은 주 이미지가 0번이 아닐 수 있다.
  static func decode(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
    return CGImageSourceCreateImageAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), options)
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
