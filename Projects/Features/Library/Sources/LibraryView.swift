import SwiftUI

public struct LibraryView: View {
  @State private var model: LibraryModel

  public init(model: LibraryModel) {
    self._model = State(initialValue: model)
  }

  public var body: some View {
    NavigationStack {
      Group {
        switch self.model.access {
        case .authorized, .limited:
          ContentUnavailableView(
            "스크린샷 \(self.model.screenshotCount)장",
            systemImage: "photo.stack",
            description: Text("자동 분류는 곧 추가됩니다.")
          )
        case .denied:
          ContentUnavailableView(
            "사진 접근 권한이 필요해요",
            systemImage: "lock",
            description: Text("설정 앱에서 사진 접근을 허용해 주세요.")
          )
        case .notDetermined:
          Button("스크린샷 정리 시작하기") {
            Task { await self.model.startButtonTapped() }
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .navigationTitle("SnapSort")
    }
    .task { await self.model.onAppear() }
  }
}
