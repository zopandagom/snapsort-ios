import PhotoLibraryInterface
import Photos
import PhotosUI
import UIKit

/// PhotoKit 기반 구현.
public struct PhotoLibraryClientImpl: PhotoLibraryClient {
  public init() {}

  public func accessState() -> PhotoAccessState {
    Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  public func requestAccess() async -> PhotoAccessState {
    await Self.map(PHPhotoLibrary.requestAuthorization(for: .readWrite))
  }

  /// 스크린샷 여부는 조회 필터가 아니라 분류 신호이므로 `.image` 전체를 가져온다 (영상 제외).
  /// 보관함이 크면 조회가 수백 ms 걸리므로 메인 스레드 밖에서 실행한다.
  @concurrent
  public func fetchImageIdentifiers() async -> [String] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    let result = PHAsset.fetchAssets(with: .image, options: options)
    var identifiers: [String] = []
    identifiers.reserveCapacity(result.count)
    result.enumerateObjects { asset, _, _ in
      identifiers.append(asset.localIdentifier)
    }
    return identifiers
  }

  /// 시스템 선택 화면은 UIKit 화면 위에 띄워야 하므로, 활성 창에서 가장 위에 떠 있는 화면을 찾아 그 위에 띄운다.
  /// 고른 식별자는 Interface 계약대로 버린다. 고른 사진이 바뀌면 PhotoKit 변경 알림으로 전달된다.
  @MainActor
  public func presentLimitedLibraryPicker() async {
    guard let presenter = Self.topViewController() else { return }
    _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
  }

  /// 비교 기준 조회와 등록은 보관함 크기에 따라 비용이 있으므로 메인 스레드 밖에서 실행한다.
  /// 관찰 객체는 스트림이 끝날 때(onTermination) 등록을 해제하므로, 그때까지 이 클로저가 붙잡아 둔다.
  @concurrent
  public func imageChanges() async -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let observer = ImageChangeObserver(continuation: continuation)
    PHPhotoLibrary.shared().register(observer)
    continuation.onTermination = { _ in
      PHPhotoLibrary.shared().unregisterChangeObserver(observer)
    }
    return stream
  }

  @MainActor
  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  static func map(_ status: PHAuthorizationStatus) -> PhotoAccessState {
    switch status {
    case .authorized: .authorized
    case .limited: .limited
    case .notDetermined: .notDetermined
    default: .denied
    }
  }
}
