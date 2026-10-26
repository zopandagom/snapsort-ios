import Foundation
import OnboardingFeature
import PhotoLibraryTesting
import SwiftUI

/// Example 앱 시나리오. 실행 인자 `-scenario <rawValue>` 로 고른다(예: `xcrun simctl launch <기기> <번들> -scenario denied`).
enum ExampleScenario: String {
  /// 기본. 첫 화면에서 "정리 시작하기"를 누르면 제한 접근으로 허용된 것처럼 보관함 화면으로 간다.
  case standard
  /// 첫 화면에서 누르면 거부한 것처럼 거부 안내와 "설정 열기"가 보인다.
  case requestDenied
  /// 권한 요청이 2초 걸린다(팝업이 뜨기까지). 누른 직후 버튼이 흐려지고 2초 뒤 보관함 화면으로 간다.
  case slowRequest
  /// 거부 화면에서 시작한다. 앱이 백그라운드로 가면 설정에서 허용한 것처럼 권한을 바꿔, 돌아오면 보관함 화면으로 간다.
  case denied
  /// 스크린 타임·기기 관리로 제한된 화면. 이유만 알리고 버튼이 없다.
  case restricted

  static var current: ExampleScenario {
    UserDefaults.standard.string(forKey: "scenario").flatMap(ExampleScenario.init(rawValue:)) ?? .standard
  }

  var photoLibrary: PhotoLibraryClientFake {
    switch self {
    case .standard:
      PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .limited)
    case .requestDenied:
      PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .denied)
    case .slowRequest:
      PhotoLibraryClientFake(
        currentState: .notDetermined,
        stateAfterRequest: .authorized,
        requestGate: { try? await Task.sleep(for: .seconds(2)) }
      )
    case .denied:
      PhotoLibraryClientFake(currentState: .denied)
    case .restricted:
      PhotoLibraryClientFake(currentState: .restricted)
    }
  }
}

/// 실제 권한 팝업 없이 온보딩 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
/// 시나리오는 실행 인자 `-scenario <이름>` 으로 고른다(`ExampleScenario`).
@main
struct OnboardingFeatureExampleApp: App {
  private static let scenario = ExampleScenario.current
  private static let photoLibrary = Self.scenario.photoLibrary

  @State private var model = OnboardingModel(photoLibrary: Self.photoLibrary)
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      // App 의 화면 전환을 흉내 낸다: 읽을 수 있는 권한이 생기면 보관함 화면 대신 결과를 보여준다.
      if self.model.access.canRead {
        ContentUnavailableView("보관함 화면으로 이동", systemImage: "checkmark.circle")
      } else {
        OnboardingView(model: self.model)
      }
    }
    // `denied`: 설정 앱에서 허용하고 돌아오는 흐름을 흉내 낸다. 앞으로 돌아오면 OnboardingView 가 다시 읽는다.
    .onChange(of: self.scenePhase) { _, phase in
      if Self.scenario == .denied, phase == .background {
        Self.photoLibrary.changeAccessState(.authorized)
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

#Preview("권한 제한") {
  OnboardingView(model: OnboardingModel(photoLibrary: PhotoLibraryClientFake(currentState: .restricted)))
}
