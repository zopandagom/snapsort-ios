import SwiftUI

/// Model 은 App 이 소유하고 주입한다. @Observable 이므로 View 는 참조만 들고 있어도 변경을 관찰한다.
public struct LibraryView: View {
  let model: LibraryModel

  public init(model: LibraryModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "이미지 \(self.model.imageCount)장",
        systemImage: "photo.stack",
        description: Text("자동 분류는 곧 추가됩니다.")
      )
      .navigationTitle("SnapSort")
    }
    .task { await self.model.onAppear() }
  }
}
