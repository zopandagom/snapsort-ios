import Core
import PhotoLibraryInterface
import PhotoLibraryTesting

extension PhotoLibraryClientFake {
  static let previewAuthorized = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: .stubs(count: 128),
    loadImageResults: PreviewPhotos.loadImageResults
  )

  /// 읽기가 끝나지 않는다. 상세의 불러오는 중을 확인한다.
  static let previewLoadingForever = PhotoLibraryClientFake(
    currentState: .authorized,
    loadImageResults: PreviewPhotos.loadImageResults,
    loadGate: { _ in
      try? await Task.sleep(for: .seconds(3600))
    }
  )

  /// 모든 이미지가 iCloud 에만 있다. 칸의 대체 심볼을 확인한다.
  static let previewInCloudOnly = PhotoLibraryClientFake(
    currentState: .authorized,
    loadImageResults: PreviewPhotos.loadImageResults.mapValues { _ in .failure(.notAvailableLocally) }
  )

  /// 분류 결과의 이미지가 모두 iCloud 에만 있다. `-scenario homeInCloudOnly` 에서 보관함 카드의 대체 표시를 본다.
  static let previewHomeInCloudOnly = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: .stubs(count: 128),
    loadImageResults: PreviewPhotos.loadImageResults.mapValues { _ in .failure(.notAvailableLocally) }
  )

  /// 이미지 읽기가 1.5초 걸린다. `-scenario homeSlowThumbnails` 에서 보관함 카드 칸이 중립 면에서 사진으로 바뀌는 것을 본다.
  static let previewSlowThumbnails = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: .stubs(count: 128),
    loadImageResults: PreviewPhotos.loadImageResults,
    loadGate: { _ in
      try? await Task.sleep(for: .seconds(1.5))
    }
  )

  /// 모든 이미지를 읽지 못한다. 상세의 실패를 확인한다.
  static let previewFailing = PhotoLibraryClientFake(
    currentState: .authorized,
    loadImageResults: PreviewPhotos.loadImageResults.mapValues { _ in .failure(.failed) }
  )

  /// 제한 접근이지만 분류 결과의 이미지를 모두 읽을 수 있다. `-scenario limited` 에서 여행 목록 안내를 본다.
  static let previewLimitedClassified = PhotoLibraryClientFake(
    currentState: .limited,
    imageAssets: .stubs(count: 128),
    loadImageResults: PreviewPhotos.loadImageResults
  )

  /// "사진 더 선택"을 누르면 고른 사진이 늘어난 것처럼 보이게 한다.
  static let previewLimited = PhotoLibraryClientFake(
    currentState: .limited,
    imageAssets: .stubs(count: 12),
    imageAssetsAfterPicker: .stubs(count: 30)
  )
}
