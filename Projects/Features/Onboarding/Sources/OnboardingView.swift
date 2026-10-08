import SwiftUI
import UIKit

/// 권한을 아직 묻지 않았거나 거부된 상태를 보여준다.
/// 읽을 수 있는 권한이 생기면 App 이 보관함 화면으로 바꾸므로 여기서는 그 상태를 그리지 않는다.
public struct OnboardingView: View {
  let model: OnboardingModel

  @Environment(\.openURL) private var openURL

  public init(model: OnboardingModel) {
    self.model = model
  }

  public var body: some View {
    switch self.model.access {
    case .notDetermined:
      ContentUnavailableView {
        Label("사진 보관함, 알아서 정리해 드릴게요", systemImage: "photo.stack")
      } description: {
        Text("보관함의 이미지를 기기 안에서 분석해 분류합니다.\n사진과 사진 속 글자는 기기 밖으로 나가지 않아요.")
      } actions: {
        Button("정리 시작하기") {
          Task { await self.model.startButtonTapped() }
        }
        .buttonStyle(.borderedProminent)
      }
    case .denied:
      ContentUnavailableView {
        Label("사진 접근 권한이 필요해요", systemImage: "lock")
      } description: {
        Text("설정 앱에서 사진 접근을 허용해 주세요.")
      } actions: {
        Button("설정 열기") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            self.openURL(url)
          }
        }
        .buttonStyle(.borderedProminent)
      }
    case .authorized, .limited:
      EmptyView()
    }
  }
}
