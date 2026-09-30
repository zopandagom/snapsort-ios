import Photos

/// 사진 보관함에서 스크린샷만 조회한다.
/// 전체 사진을 훑지 않고 mediaSubtypes 필터를 PhotoKit 쿼리에 넘겨 인덱싱 비용을 줄인다.
struct ScreenshotLibrary: Sendable {
  enum AccessState: Sendable {
    case authorized
    case limited
    case denied
    case notDetermined
  }

  func accessState() -> AccessState {
    Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  func requestAccess() async -> AccessState {
    await Self.map(PHPhotoLibrary.requestAuthorization(for: .readWrite))
  }

  /// 최신순 스크린샷 목록. PHAsset 은 Sendable 이 아니므로 식별자만 넘긴다.
  func fetchScreenshotIdentifiers() -> [String] {
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

  private static func map(_ status: PHAuthorizationStatus) -> AccessState {
    switch status {
    case .authorized: .authorized
    case .limited: .limited
    case .notDetermined: .notDetermined
    default: .denied
    }
  }
}
