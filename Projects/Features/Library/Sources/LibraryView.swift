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
      .safeAreaInset(edge: .top) {
        if self.model.isLimited {
          self.limitedAccessBanner
        }
      }
    }
    .task { await self.model.onAppear() }
  }

  private var limitedAccessBanner: some View {
    HStack(spacing: 12) {
      Label("선택한 사진만 분류합니다", systemImage: "photo.badge.checkmark")
        .font(.subheadline)
      Spacer()
      Button("사진 더 선택") {
        Task { await self.model.selectMorePhotosTapped() }
      }
      .buttonStyle(.bordered)
      .font(.subheadline)
    }
    .padding()
    .background(.thinMaterial, in: .rect(cornerRadius: 12))
    .padding(.horizontal)
  }
}
