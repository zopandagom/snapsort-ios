import LibraryFeature
import PhotoLibraryTesting
import SwiftUI

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
@main
struct LibraryFeatureExampleApp: App {
  @State private var model = LibraryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized)

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

#Preview("이미지 있음") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized))
}

#Preview("제한 접근") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake.previewLimited))
}

#Preview("이미지 없음") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake(currentState: .authorized)))
}
