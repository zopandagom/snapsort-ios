import OnboardingFeature
import PhotoLibraryTesting
import SwiftUI

/// 실제 권한 팝업 없이 온보딩 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
@main
struct OnboardingFeatureExampleApp: App {
  @State private var model = OnboardingModel(
    photoLibrary: PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .limited)
  )

  var body: some Scene {
    WindowGroup {
      // App 의 화면 전환을 흉내 낸다: 읽을 수 있는 권한이 생기면 보관함 화면 대신 결과를 보여준다.
      if self.model.access.canRead {
        ContentUnavailableView("보관함 화면으로 이동", systemImage: "checkmark.circle")
      } else {
        OnboardingView(model: self.model)
      }
    }
  }
}

#Preview("권한 요청 전") {
  OnboardingView(model: OnboardingModel(photoLibrary: PhotoLibraryClientFake()))
}

#Preview("권한 거부") {
  OnboardingView(model: OnboardingModel(photoLibrary: PhotoLibraryClientFake(currentState: .denied)))
}
