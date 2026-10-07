import LibraryFeature
import PhotoLibraryImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SnapSortApp: App {
  @State private var libraryModel = LibraryModel(photoLibrary: PhotoLibraryClientImpl())

  var body: some Scene {
    WindowGroup {
      LibraryView(model: self.libraryModel)
    }
  }
}
