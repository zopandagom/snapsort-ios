import IndexingInterface
import IndexingTesting
import LibraryFeature
import PhotoLibraryTesting
import SwiftUI

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
@main
struct LibraryFeatureExampleApp: App {
  @State private var model = LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress
  )

  var body: some Scene {
    WindowGroup {
      LibraryView(model: self.model)
    }
  }
}

extension PhotoLibraryClientFake {
  static let previewAuthorized = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: .stubs(count: 128)
  )

  /// "사진 더 선택"을 누르면 고른 사진이 늘어난 것처럼 보이게 한다.
  static let previewLimited = PhotoLibraryClientFake(
    currentState: .limited,
    imageAssets: .stubs(count: 12),
    imageAssetsAfterPicker: .stubs(count: 30)
  )
}

extension IndexingClientFake {
  /// 128장 중 40장을 분석한 상태. 진행률 표시는 보관함 카테고리 화면 작업에서 붙인다.
  static let previewInProgress = IndexingClientFake(progress: [
    IndexingProgress(totalCount: 128, indexedCount: 40, skippedCount: 0),
  ])
}

#Preview("이미지 있음") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress
  ))
}

#Preview("제한 접근") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake.previewLimited, indexing: nil))
}

#Preview("이미지 없음") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake(currentState: .authorized), indexing: nil))
}
