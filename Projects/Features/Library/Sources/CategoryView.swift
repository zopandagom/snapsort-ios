import Core
import DesignSystem
import SwiftUI

/// 카테고리 화면: 그 카테고리 이미지를 생성일의 연·월 섹션으로 나눈 최신순 썸네일 격자 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 쇼핑·대화·지도는 툴바 메뉴로 쇼핑몰별·브랜드별 / 앱별 / 지역별 묶기를 고를 수 있다(선택은 저장하지 않는 화면 일시 상태).
/// 칸을 누르면 사진 상세로 간다(이동 목적지는 LibraryView 가 루트에 둔다).
/// 기프티콘은 이 격자 대신 `GifticonListView`, 영수증은 `ReceiptListView`, 여행은 `TripListView` 로 연다.
/// body 는 `content` 만 읽고 썸네일은 칸(`CategoryThumbnailCell`)이 읽어, 썸네일 하나가 끝날 때 섹션 전체를 다시 그리지 않는다.
public struct CategoryView: View {
  let model: CategoryModel
  let category: ImageCategory

  /// 위쪽에 보이는 칸. 위에 새 사진이 더해져도 보던 칸이 그대로 있게 하는 화면 일시 상태다.
  /// 지역별 묶기에서는 같은 이미지가 두 섹션에 들 수 있어 섹션과 이미지 쌍으로 칸을 가른다.
  @State private var anchorID: GridCellID?
  /// 고른 묶기. nil 이면 월별. 새로 열면 월별이고 상세에서 돌아오면 그대로다.
  @State private var grouping: CaptureGrouping?

  public init(model: CategoryModel, category: ImageCategory) {
    self.model = model
    self.category = category
  }

  public var body: some View {
    self.contentView
      .navigationTitle(self.category.title)
      .snapScreenBackground()
      // 위쪽 inset 막대를 두지 않고 툴바 메뉴로 고른다(영수증 목록과 같다).
      .toolbar {
        let groupings = CaptureGrouping.groupings(for: self.category)
        if !groupings.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Picker("묶기", selection: self.$grouping) {
                Text("월별").tag(CaptureGrouping?.none)
                ForEach(groupings, id: \.self) { grouping in
                  Text(grouping.menuTitle).tag(CaptureGrouping?.some(grouping))
                }
              }
            } label: {
              Label("묶기", systemImage: "rectangle.3.group")
            }
          }
        }
      }
      .onChange(of: self.grouping) { self.anchorID = nil }
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
      self.grid(self.gridSections(sections))
        // 묶기를 바꾸면 ScrollView 를 새로 만들어 맨 위부터 보인다.
        .id(self.grouping)
    case .failed:
      StatusMessageView("사진을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    }
  }

  /// 고른 묶기의 섹션. 이 카테고리에 없는 묶기면 월별이다.
  private func gridSections(_ sections: CategorySections) -> [GridSection] {
    if let grouping = self.grouping, let groups = sections.groups[grouping] {
      return groups.map { section in
        GridSection(
          id: AnyHashable(section.id),
          title: Text(verbatim: "\(section.title(for: grouping)) · \(section.assets.count)장"),
          assets: section.assets,
          showsCheckingFooter: section.kind == .checking
        )
      }
    }
    return sections.months.map { section in
      GridSection(
        id: AnyHashable(section.id),
        title: self.monthTitle(section),
        assets: section.assets,
        showsCheckingFooter: false
      )
    }
  }

  private func grid(_ sections: [GridSection]) -> some View {
    ScrollView {
      LazyVGrid(columns: ThumbnailGrid.columns, spacing: ThumbnailGrid.spacing, pinnedViews: [.sectionHeaders]) {
        ForEach(sections, id: \.id) { section in
          Section {
            ForEach(section.cells) { cell in
              NavigationLink(value: PhotoDetailRoute(asset: cell.asset)) {
                CategoryThumbnailCell(model: self.model, asset: cell.asset, category: self.category)
              }
              .buttonStyle(.plain)
            }
          } header: {
            self.header(section.title)
          } footer: {
            if section.showsCheckingFooter {
              Text("글자를 읽으면 묶습니다. iCloud 에만 있는 사진은 기기에 내려받은 뒤 확인합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
          }
        }
      }
      .scrollTargetLayout()
    }
    .scrollPosition(id: self.$anchorID, anchor: .top)
  }

  /// 기기 달력·로캘로 연·월을 쓴다(Model 의 기본 달력 `.autoupdatingCurrent` 와 같다).
  private func monthTitle(_ section: ImageMonthSection) -> Text {
    if section.month != nil, let date = section.assets.first?.creationDate {
      Text(date, format: .dateTime.year().month(.wide))
    } else {
      Text("날짜 없음")
    }
  }

  private func header(_ title: Text) -> some View {
    title
      .font(.headline)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, 8)
      // 고정 머리글이 지나가는 썸네일을 가리도록 화면 바탕과 같은 불투명 색을 쓴다.
      .background(SnapColor.background)
  }
}

/// 격자 한 섹션. 월별과 묶기별이 같은 모양으로 그린다.
private struct GridSection {
  let id: AnyHashable
  let title: Text
  let assets: [ImageAsset]
  /// 확인 중 섹션이면 꼬리 문구를 붙인다.
  let showsCheckingFooter: Bool

  var cells: [GridCell] {
    self.assets.map { GridCell(id: GridCellID(section: self.id, image: $0.id), asset: $0) }
  }
}

private struct GridCell: Identifiable {
  let id: GridCellID
  let asset: ImageAsset
}

/// 격자 칸 식별. 같은 이미지가 두 섹션에 들 수 있어(지역별) 섹션과 이미지 쌍으로 가른다.
private struct GridCellID: Hashable {
  let section: AnyHashable
  let image: ImageAsset.ID
}

private extension CaptureGrouping {
  /// 툴바 메뉴 항목 이름.
  var menuTitle: String {
    switch self {
    case .mall: "쇼핑몰별"
    case .brand: "브랜드별"
    case .chatApp: "앱별"
    case .region: "지역별"
    }
  }
}

private extension CaptureGroupSection {
  /// 섹션 머리 이름. 모름은 묶기별 문구다.
  func title(for grouping: CaptureGrouping) -> String {
    switch self.kind {
    case let .group(key): key.title
    case .checking: "확인 중"
    case .unknown:
      switch grouping {
      case .mall: "쇼핑몰 모름"
      case .brand: "브랜드 모름"
      case .chatApp: "앱 모름"
      case .region: "지역 모름"
      }
    }
  }
}

/// 사진 상세로 가는 이동 값. 상세는 카테고리 화면·여행 폴더 상세의 칸과 기프티콘·영수증 목록의 줄, 검색 결과의 사진 줄, 정리 화면의 후보 줄에서만 연다.
struct PhotoDetailRoute: Hashable {
  let asset: ImageAsset
  /// 기프티콘 목록·정리 화면에서 열 때만 그 항목. 이때만 상세가 기프티콘 정보·사용함 버튼·바코드를 보인다.
  /// 다른 카테고리 격자에서 연 같은 이미지에는 주소·번호 행동만 보인다.
  var gifticon: GifticonListItem?
}

/// 격자 칸 하나. 보일 때 썸네일을 읽는다. 사라지면(`.task` 취소) 읽는 중이면 취소하고, 읽었으면 Model 이 최근 64장까지 남긴다.
struct CategoryThumbnailCell: View {
  let model: CategoryModel
  let asset: ImageAsset
  let scope: ThumbnailScope

  init(model: CategoryModel, asset: ImageAsset, category: ImageCategory) {
    self.init(model: model, asset: asset, scope: .category(category))
  }

  init(model: CategoryModel, asset: ImageAsset, scope: ThumbnailScope) {
    self.model = model
    self.asset = asset
    self.scope = scope
  }

  var body: some View {
    ThumbnailTile(self.tileContent, accessibilityLabel: self.accessibilityLabel)
      .task { await self.model.thumbnailAppeared(id: self.asset.id, scope: self.scope) }
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
