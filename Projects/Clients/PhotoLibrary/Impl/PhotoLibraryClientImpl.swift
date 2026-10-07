import PhotoLibraryInterface
import Photos

/// PhotoKit 기반 구현.
/// 전체 사진을 훑지 않고 mediaSubtypes 필터를 PhotoKit 쿼리에 넘겨 인덱싱 비용을 줄인다.
public struct PhotoLibraryClientImpl: PhotoLibraryClient {
  public init() {}

  public func accessState() -> PhotoAccessState {
    Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  public func requestAccess() async -> PhotoAccessState {
    await Self.map(PHPhotoLibrary.requestAuthorization(for: .readWrite))
  }

  /// 보관함이 크면 조회가 수백 ms 걸리므로 메인 스레드 밖에서 실행한다.
  @concurrent
  public func fetchScreenshotIdentifiers() async -> [String] {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "(mediaSubtypes & %d) != 0",
      PHAssetMediaSubtype.photoScreenshot.rawValue
    )
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    let result = PHAsset.fetchAssets(with: .image, options: options)
    var identifiers: [String] = []
    identifiers.reserveCapacity(result.count)
    result.enumerateObjects { asset, _, _ in
      identifiers.append(asset.localIdentifier)
    }
    return identifiers
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
