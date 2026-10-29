import Core
import DesignSystem
import SwiftUI

/// 여행 폴더 목록: 최신 여행이 위인 줄마다 대표 썸네일·제목(장소 이름 또는 기간)·기간·사진 수 (docs/ARCHITECTURE.md §4 여행 폴더).
/// 줄을 누르면 여행 폴더 상세(`TripDetailView`)로 간다(이동 목적지는 LibraryView 가 루트에 둔다).
/// 장소 이름은 캐시된 것만 보이고(상세·미리 받기가 쓴다), 이 화면은 묻지 않는다.
/// 썸네일은 카테고리 화면과 같은 보관 규칙을 쓰도록 `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(category: .travel)`).
public struct TripListView: View {
  let model: TripListModel
  let categoryModel: CategoryModel

  public init(model: TripListModel, categoryModel: CategoryModel) {
    self.model = model
    self.categoryModel = categoryModel
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(ImageCategory.travel.title)
      .snapScreenBackground()
      .task { await self.model.onAppear() }
      .task { await self.categoryModel.thumbnailScreenAppeared(category: .travel) }
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.model.content {
    case .loading:
      SnapLoadingDots()
    case .failed:
      StatusMessageView("여행을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    case let .loaded(items) where items.isEmpty:
      StatusMessageView(
        "여행 없음",
        glyph: ImageCategory.travel.glyph,
        description: self.model.isLimited ? Self.limitedNotice : "자주 가는 지역 밖에서 찍은 사진을 여행으로 묶습니다."
      )
    case .loaded where self.categoryModel.category != .travel:
      // 지난 카테고리의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 줄을 그린다(`CategoryView.content` 와 같은 이유).
      SnapLoadingDots()
    case let .loaded(items):
      self.list(items)
    }
  }

  private func list(_ items: [TripFolderItem]) -> some View {
    SnapList {
      if self.model.isLimited {
        Section {
          Label(Self.limitedNotice, systemImage: "photo.badge.checkmark")
            .font(.subheadline)
        }
      }
      Section {
        ForEach(items) { item in
          NavigationLink(value: TripFolderRoute(trip: item.trip)) {
            TripFolderRow(categoryModel: self.categoryModel, item: item, calendar: self.model.calendar)
          }
        }
      }
    }
  }

  /// 여행은 고른 사진만으로 판정한다 (docs/ARCHITECTURE.md §4 여행 판정).
  private static let limitedNotice = "선택한 사진만으로 여행을 찾아 정확하지 않을 수 있습니다."
}

/// 여행 폴더 한 줄. 이름이 없으면 기간을 제목으로 쓴다.
struct TripFolderRow: View {
  let categoryModel: CategoryModel
  let item: TripFolderItem
  let calendar: Calendar

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let cover = self.item.cover {
          CategoryThumbnailCell(model: self.categoryModel, asset: cover, category: .travel)
        } else {
          ThumbnailTile(
            .placeholder(systemImage: ImageCategory.travel.systemImage),
            accessibilityLabel: Text("대표 사진 없음")
          )
        }
      }
      .frame(width: 56, height: 56)
      .clipShape(.rect(cornerRadius: 8))
      // 썸네일 칸의 라벨(촬영 날짜)이 기간과 겹쳐 두 번 읽히므로 이 줄에서만 숨긴다.
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        if let placeName = self.item.placeName {
          Text(placeName)
            .lineLimit(1)
          Text("\(TripPeriodText.text(self.item.period, calendar: self.calendar)) · 사진 \(self.item.photoCount)장")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          TripPeriodText.text(self.item.period, calendar: self.calendar)
            .lineLimit(1)
          Text("사진 \(self.item.photoCount)장")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

/// 여행 폴더 상세로 가는 이동 값. 목록에서 누른 그때의 여행이고, 상세가 저장소에서 사진이 겹치는 여행을 다시 찾는다.
struct TripFolderRoute: Hashable {
  let trip: Trip
}

enum TripPeriodText {
  /// 기간의 첫날~마지막 날. 하루면 그날만 쓴다. 날짜 형식은 만료일과 같다(`GifticonExpiryText.date`: 그날 정오를 기기 달력으로 형식화).
  static func text(_ period: TripPeriod, calendar: Calendar) -> Text {
    let first = GifticonExpiryText.date(period.firstDay, calendar: calendar)
    guard period.lastDay != period.firstDay else { return first }
    return Text("\(first) ~ \(GifticonExpiryText.date(period.lastDay, calendar: calendar))")
  }
}
