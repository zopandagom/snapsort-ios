import Core
import DesignSystem
import SwiftUI

/// 사진 상세: 기기에 있는 가장 큰 버전으로 한 장을 크게 보인다 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// iCloud 원본은 내려받지 않는다. 작은 대체 버전이면 안내를 붙이고, 기기 버전이 없으면 볼 수 없다고 보인다.
/// 닫히면(`.task` 취소) Model 이 이미지를 놓는다.
public struct PhotoDetailView: View {
  let model: CategoryModel
  let asset: ImageAsset

  public init(model: CategoryModel, asset: ImageAsset) {
    self.model = model
    self.asset = asset
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(self.title)
      .navigationBarTitleDisplayMode(.inline)
      .task { await self.model.detailAppeared(id: self.asset.id) }
  }

  /// 다른 사진의 상세 상태가 남아 있으면 쓰지 않고 불러오는 중으로 그린다.
  private var state: ImageLoadState {
    guard let detail = self.model.detail, detail.id == self.asset.id else { return .loading }
    return detail.state
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.state {
    case .loading:
      ProgressView()
    case let .loaded(image):
      VStack(spacing: 12) {
        Image(decorative: image.cgImage, orientation: image.orientation)
          .resizable()
          .scaledToFit()
        if image.isLocalFallback {
          // 문구가 상태를 말하므로 심볼은 VoiceOver 에서 읽지 않는다.
          Label("iCloud 원본 대신 기기에 있는 작은 버전입니다", systemImage: "icloud")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("iCloud 원본 대신 기기에 있는 작은 버전입니다"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
      }
    case .unavailable(.inCloudOnly):
      StatusMessageView(
        "iCloud 에만 있는 사진입니다",
        systemImage: "icloud.slash",
        description: "사진 앱에서 내려받으면 볼 수 있습니다."
      )
    case .unavailable(.notFound):
      StatusMessageView("보관함에 없는 사진입니다", systemImage: "photo.badge.exclamationmark")
    case .unavailable(.failed):
      // 다시 시도는 두지 않는다. 닫고 다시 열면 다시 읽는다.
      StatusMessageView("사진을 불러오지 못했습니다", systemImage: "exclamationmark.triangle")
    }
  }

  private var title: Text {
    if let date = self.asset.creationDate {
      Text(date, format: .dateTime.year().month().day().hour().minute())
    } else {
      Text("날짜 없음")
    }
  }
}
