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
    imageIdentifiers: (0 ..< 128).map { "image-\($0)" }
  )
}

#Preview("이미지 있음") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized))
}

#Preview("이미지 없음") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake(currentState: .authorized)))
}
