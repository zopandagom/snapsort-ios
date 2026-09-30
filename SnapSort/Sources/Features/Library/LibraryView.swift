import SwiftUI

struct LibraryView: View {
  @State private var accessState: ScreenshotLibrary.AccessState = .notDetermined
  @State private var screenshotCount = 0

  private let library = ScreenshotLibrary()

  var body: some View {
    NavigationStack {
      Group {
        switch self.accessState {
        case .authorized, .limited:
          ContentUnavailableView(
            "스크린샷 \(self.screenshotCount)장",
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
            Task { await self.requestAccess() }
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .navigationTitle("SnapSort")
    }
    .task {
      self.accessState = self.library.accessState()
      self.reloadCount()
    }
  }

  private func requestAccess() async {
    self.accessState = await self.library.requestAccess()
    self.reloadCount()
  }

  private func reloadCount() {
    guard self.accessState == .authorized || self.accessState == .limited else { return }
    self.screenshotCount = self.library.fetchScreenshotIdentifiers().count
  }
}

#Preview {
  LibraryView()
}
