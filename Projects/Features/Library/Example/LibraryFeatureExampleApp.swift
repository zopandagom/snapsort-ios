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
    screenshotIdentifiers: (0 ..< 128).map { "screenshot-\($0)" }
  )
}

#Preview("권한 허용") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized))
}

#Preview("권한 거부") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake(currentState: .denied)))
}

#Preview("권한 요청 전") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake()))
}
