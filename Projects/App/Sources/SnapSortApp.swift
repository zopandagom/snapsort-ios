import LibraryFeature
import OnboardingFeature
import PhotoLibraryImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SnapSortApp: App {
  @State private var onboardingModel: OnboardingModel
  @State private var libraryModel: LibraryModel

  init() {
    let photoLibrary = PhotoLibraryClientImpl()
    self._onboardingModel = State(initialValue: OnboardingModel(photoLibrary: photoLibrary))
    self._libraryModel = State(initialValue: LibraryModel(photoLibrary: photoLibrary))
  }

  var body: some Scene {
    WindowGroup {
      // 화면 간 흐름은 App 이 정한다. 읽을 수 있는 권한이 생기면 보관함으로 넘어간다.
      if self.onboardingModel.access.canRead {
        LibraryView(model: self.libraryModel)
      } else {
        OnboardingView(model: self.onboardingModel)
      }
    }
  }
}
