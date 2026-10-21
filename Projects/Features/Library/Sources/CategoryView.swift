import Core
import DesignSystem
import SwiftUI

/// 카테고리 화면: 그 카테고리 이미지를 생성일의 연·월 섹션으로 나눈 최신순 썸네일 격자 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 칸을 누르면 사진 상세로 간다(이동 목적지는 LibraryView 가 루트에 둔다). 기프티콘은 이 격자 대신 `GifticonListView` 로 연다.
/// body 는 `content` 만 읽고 썸네일은 칸(`CategoryThumbnailCell`)이 읽어, 썸네일 하나가 끝날 때 섹션 전체를 다시 그리지 않는다.
public struct CategoryView: View {
  let model: CategoryModel
  let category: ImageCategory

  /// 위쪽에 보이는 칸. 위에 새 사진이 더해져도 보던 칸이 그대로 있게 하는 화면 일시 상태다.
  @State private var anchorID: ImageAsset.ID?

  public init(model: CategoryModel, category: ImageCategory) {
    self.model = model
    self.category = category
  }

  public var body: some View {
    self.contentView
      .navigationTitle(self.category.title)
      .task { await self.model.onAppear(category: self.category) }
  }

  /// 다른 카테고리를 막 연 첫 프레임에 지난 카테고리 내용이 비치지 않게, 이 카테고리일 때만 Model 의 내용을 쓴다.
  private var content: CategoryContent {
    self.model.category == self.category ? self.model.content : .loading
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.content {
    case .loading:
      ProgressView()
    case let .loaded(sections) where sections.isEmpty:
      StatusMessageView(
        "이미지 없음",
        systemImage: "photo.on.rectangle.angled",
        description: "이 카테고리에 분류된 이미지가 없습니다."
      )
    case let .loaded(sections):
      self.grid(sections)
    case .failed:
      StatusMessageView("사진을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    }
  }

  private func grid(_ sections: [ImageMonthSection]) -> some View {
    ScrollView {
      LazyVGrid(columns: ThumbnailGrid.columns, spacing: ThumbnailGrid.spacing, pinnedViews: [.sectionHeaders]) {
        ForEach(sections) { section in
          Section {
            ForEach(section.assets) { asset in
              NavigationLink(value: PhotoDetailRoute(asset: asset)) {
                CategoryThumbnailCell(model: self.model, asset: asset, category: self.category)
              }
              .buttonStyle(.plain)
            }
          } header: {
            self.header(section)
          }
        }
      }
      .scrollTargetLayout()
    }
    .scrollPosition(id: self.$anchorID, anchor: .top)
  }

  /// 기기 달력·로캘로 연·월을 쓴다(Model 의 기본 달력 `.autoupdatingCurrent` 와 같다).
  private func header(_ section: ImageMonthSection) -> some View {
    Group {
      if section.month != nil, let date = section.assets.first?.creationDate {
        Text(date, format: .dateTime.year().month(.wide))
      } else {
        Text("날짜 없음")
      }
    }
    .font(.headline)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }
}

/// 사진 상세로 가는 이동 값. 상세는 카테고리 화면의 칸과 기프티콘 목록의 줄에서만 연다.
struct PhotoDetailRoute: Hashable {
  let asset: ImageAsset
  /// 기프티콘 목록에서 열 때만 그 항목. 이때만 상세가 기프티콘 정보·사용함 버튼·바코드를 보인다.
  /// 다른 카테고리 격자에서 연 같은 이미지에는 주소·번호 행동만 보인다.
  var gifticon: GifticonListItem?
}

/// 격자 칸 하나. 보일 때 썸네일을 읽는다. 사라지면(`.task` 취소) 읽는 중이면 취소하고, 읽었으면 Model 이 최근 64장까지 남긴다.
struct CategoryThumbnailCell: View {
  let model: CategoryModel
  let asset: ImageAsset
  let category: ImageCategory

  var body: some View {
    ThumbnailTile(self.tileContent, accessibilityLabel: self.accessibilityLabel)
      .task { await self.model.thumbnailAppeared(id: self.asset.id, in: self.category) }
  }

  private var tileContent: ThumbnailTile.Content {
    switch self.model.thumbnails[self.asset.id] {
    case nil, .loading:
      .loading
    case let .loaded(image):
      .image(image.cgImage, orientation: image.orientation)
    case let .unavailable(reason):
      .placeholder(systemImage: reason.systemImage)
    }
  }

  private var accessibilityLabel: Text {
    if let date = self.asset.creationDate {
      Text(date, format: .dateTime.year().month().day())
    } else {
      Text("날짜 없음")
    }
  }
}

extension ImageUnavailableReason {
  /// 격자 칸의 대체 심볼.
  var systemImage: String {
    switch self {
    case .inCloudOnly: "icloud.slash"
    case .notFound: "photo.badge.exclamationmark"
    case .failed: "exclamationmark.triangle"
    }
  }
}
