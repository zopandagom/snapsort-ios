import Core
import DesignSystem
import SwiftUI

/// 여행 폴더 상세: 장소 이름(또는 기간)·기간·사진 수, 반올림 중심점 지도, 여행 사진 격자, 그 기간의 영수증·지도·문서 캡처 묶음
/// (docs/ARCHITECTURE.md §4 여행 폴더). 칸을 누르면 사진 상세(`PhotoDetailView`)로 간다.
/// `visit` 은 이 화면 인스턴스의 일시 상태다. 사진 상세에서 돌아오면 같은 값이라 Model 이 이 방문에서 받은 이름 결과를 다시 쓰고,
/// 목록에서 새로 열면 새 값이라 한 번 다시 묻는다. Model 에 남은 다른 visit 의 내용은 그리지 않는다(다른 여행을 연 첫 프레임).
/// 썸네일은 카테고리 화면과 같은 보관 규칙을 쓰도록 `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(category: .travel)`).
public struct TripDetailView: View {
  let model: TripDetailModel
  let categoryModel: CategoryModel
  let route: TripFolderRoute

  @State private var visit = UUID()

  init(model: TripDetailModel, categoryModel: CategoryModel, route: TripFolderRoute) {
    self.model = model
    self.categoryModel = categoryModel
    self.route = route
  }

  /// - Parameter trip: 목록에서 누른 여행. 저장소에서 사진이 겹치는 여행을 다시 찾아 보인다.
  public init(model: TripDetailModel, categoryModel: CategoryModel, trip: Trip) {
    self.init(model: model, categoryModel: categoryModel, route: TripFolderRoute(trip: trip))
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(ImageCategory.travel.title)
      .navigationBarTitleDisplayMode(.inline)
      .task { await self.model.onAppear(trip: self.route.trip, visit: self.visit) }
      .task { await self.categoryModel.thumbnailScreenAppeared(category: .travel) }
  }

  /// 이 화면 인스턴스의 내용일 때만 그린다. 다른 visit 의 내용이면(push 직후 `.task` 전 첫 프레임) 불러오는 중.
  private var content: TripDetailContent {
    self.model.visit == self.visit ? self.model.content : .loading
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.content {
    case .loading:
      ProgressView()
    case .failed:
      StatusMessageView("여행을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    case .notFound:
      StatusMessageView(
        "여행을 찾을 수 없습니다",
        systemImage: ImageCategory.travel.systemImage,
        description: "사진이 바뀌어 여행을 다시 찾았습니다. 여행 목록에서 다시 열어 주세요."
      )
    case .loaded where self.categoryModel.category != .travel:
      // 지난 카테고리의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 칸을 그린다(`CategoryView.content` 와 같은 이유).
      ProgressView()
    case let .loaded(detail):
      self.detailView(detail)
    }
  }

  private func detailView(_ detail: TripDetail) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        self.header(detail)
          .padding(.horizontal)
        if let center = detail.mapCenter {
          TripMapView(center: center)
            .padding(.horizontal)
        }
        if detail.photos.isEmpty, detail.captureGroups.isEmpty {
          StatusMessageView(
            "보이는 사진이 없습니다",
            systemImage: "photo.on.rectangle.angled",
            description: "여행 사진이 보관함에서 지워졌습니다."
          )
        } else {
          self.photoSection(detail)
          ForEach(detail.captureGroups) { group in
            self.section(group.category.title, assets: group.assets)
          }
        }
      }
      .padding(.vertical)
    }
  }

  @ViewBuilder
  private func header(_ detail: TripDetail) -> some View {
    let period = TripPeriodText.text(detail.period, calendar: self.model.calendar)
    VStack(alignment: .leading, spacing: 4) {
      switch self.model.placeName {
      case .loading:
        period
          .font(.title2.bold())
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text("장소 확인 중")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      case let .named(name):
        Text(name)
          .font(.title2.bold())
        period
          .font(.subheadline)
          .foregroundStyle(.secondary)
      case .unnamed, .unavailable:
        period
          .font(.title2.bold())
      }
      Text("사진 \(detail.trip.assetIDs.count)장")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func photoSection(_ detail: TripDetail) -> some View {
    if !detail.photos.isEmpty || detail.missingPhotoCount > 0 {
      VStack(alignment: .leading, spacing: 8) {
        self.section("여행 사진", assets: detail.photos)
        if detail.missingPhotoCount > 0 {
          Text("보관함에서 지워진 사진 \(detail.missingPhotoCount)장은 보이지 않습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
      }
    }
  }

  private func section(_ title: String, assets: [ImageAsset]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .padding(.horizontal)
      LazyVGrid(columns: ThumbnailGrid.columns, spacing: ThumbnailGrid.spacing) {
        ForEach(assets) { asset in
          NavigationLink(value: PhotoDetailRoute(asset: asset)) {
            CategoryThumbnailCell(model: self.categoryModel, asset: asset, category: .travel)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}
