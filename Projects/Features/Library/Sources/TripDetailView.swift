import Core
import DesignSystem
import SwiftUI

/// 여행 폴더 상세: 장소 이름(또는 기간)·기간·사진 수, 반올림 중심점 지도, 여행 사진 격자, 그 기간의 영수증·지도·문서 캡처 묶음
/// (docs/ARCHITECTURE.md §4 여행 폴더). 칸을 누르면 사진 상세(`PhotoDetailView`)로 가고, 상세는 누른 칸의 섹션(여행 사진 또는 캡처 묶음 하나) 안에서 넘긴다.
/// `visit` 은 이 화면 인스턴스의 일시 상태다. 사진 상세에서 돌아오면 같은 값이라 Model 이 이 방문에서 받은 이름 결과를 다시 쓰고,
/// 목록에서 새로 열면 새 값이라 한 번 다시 묻는다. Model 에 남은 다른 visit 의 내용은 그리지 않는다(다른 여행을 연 첫 프레임).
/// 같은 값으로 상세의 돌아올 위치(`CategoryModel.detailReturn`)가 이 화면 것인지 가르고, 돌아오면 마지막으로 본 사진의 칸이 보이게 한 번 스크롤한다.
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
      .snapScreenBackground()
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
      SnapLoadingDots()
    case .failed:
      StatusMessageView("여행을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    case .notFound:
      StatusMessageView(
        "여행을 찾을 수 없습니다",
        glyph: ImageCategory.travel.glyph,
        description: "사진이 바뀌어 여행을 다시 찾았습니다. 여행 목록에서 다시 열어 주세요."
      )
    case .loaded where self.categoryModel.category != .travel:
      // 지난 카테고리의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 칸을 그린다(`CategoryView.content` 와 같은 이유).
      SnapLoadingDots()
    case let .loaded(detail):
      self.detailView(detail)
    }
  }

  private func detailView(_ detail: TripDetail) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          self.header(detail)
            .padding(.horizontal)
          if let center = detail.mapCenter {
            TripMapView(center: center)
              .padding(.horizontal)
          }
          if detail.photos.isEmpty, detail.captureGroups.isEmpty {
            StatusMessageView(empty: "보이는 사진이 없어요", description: "여행 사진이 보관함에서 지워졌어요.")
          } else {
            self.photoSection(detail)
            ForEach(Array(detail.captureGroups.enumerated()), id: \.element.id) { offset, group in
              self.section(group.category.title, assets: group.assets, position: offset + 1)
            }
          }
        }
        .padding(.vertical)
      }
      // 상세에서 돌아와 다시 보일 때 이 방문의 돌아올 위치가 있으면 그 칸이 보이게 한 번 스크롤한다(이미 보이면 움직이지 않는다).
      // 영수증 사진은 여행 사진과 영수증 묶음에 함께 들 수 있어 연 섹션의 칸으로 가고, 지금 섹션들에 없으면 움직이지 않는다.
      .onAppear {
        guard let target = self.categoryModel.detailReturn, target.origin.visit == self.visit else { return }
        self.categoryModel.detailReturnApplied(visit: self.visit)
        let ids = [detail.photos.map(\.id)] + detail.captureGroups.map { $0.assets.map(\.id) }
        guard let section = PhotoPages.returnSection(of: target.id, preferred: target.origin.section, in: ids)
        else { return }
        proxy.scrollTo(TripCellID(section: section, image: target.id), anchor: nil)
      }
    }
  }

  @ViewBuilder
  private func header(_ detail: TripDetail) -> some View {
    let period = TripPeriodText.text(detail.period, calendar: self.model.calendar)
    VStack(alignment: .leading, spacing: 4) {
      switch self.model.placeName {
      case .loading:
        period
          .font(.snap(.title2, weight: .extraBold))
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text("장소 확인 중")
        }
        .font(.snap(.subheadline))
        .foregroundStyle(.secondary)
      case let .named(name):
        Text(name)
          .font(.snap(.title2, weight: .extraBold))
        period
          .font(.snap(.subheadline))
          .foregroundStyle(.secondary)
      case .unnamed, .unavailable:
        period
          .font(.snap(.title2, weight: .extraBold))
      }
      Text("사진 \(detail.trip.assetIDs.count)장")
        .font(.snap(.subheadline))
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func photoSection(_ detail: TripDetail) -> some View {
    if !detail.photos.isEmpty || detail.missingPhotoCount > 0 {
      VStack(alignment: .leading, spacing: 8) {
        self.section("여행 사진", assets: detail.photos, position: 0)
        if detail.missingPhotoCount > 0 {
          Text("보관함에서 지워진 사진 \(detail.missingPhotoCount)장은 보이지 않습니다.")
            .font(.snap(.footnote))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
      }
    }
  }

  /// - Parameter position: 섹션 위치. 여행 사진이 0(비어 있어도 자리를 둔다), 캡처 묶음이 1부터.
  private func section(_ title: String, assets: [ImageAsset], position: Int) -> some View {
    let pages = PhotoPages.pages(assets)
    let origin = PhotoDetailOrigin(visit: self.visit, section: position)
    return VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.snap(.headline, weight: .bold))
        .padding(.horizontal)
      LazyVGrid(columns: ThumbnailGrid.columns, spacing: ThumbnailGrid.spacing) {
        ForEach(TripCell.cells(assets, section: position)) { cell in
          NavigationLink(value: PhotoDetailRoute(pages: pages, index: cell.index, origin: origin)) {
            CategoryThumbnailCell(model: self.categoryModel, asset: cell.asset, category: .travel)
              .photoZoomSource(cell.asset.id)
          }
          .buttonStyle(.plain)
          .environment(\.photoDetailOrigin, origin)
        }
      }
    }
  }
}

/// 격자 칸 하나.
private struct TripCell: Identifiable {
  let id: TripCellID
  let asset: ImageAsset
  /// 섹션 안 위치. 상세의 처음 장이다.
  let index: Int

  static func cells(_ assets: [ImageAsset], section: Int) -> [TripCell] {
    assets.enumerated().map { index, asset in
      TripCell(id: TripCellID(section: section, image: asset.id), asset: asset, index: index)
    }
  }
}

/// 격자 칸 식별. 위치가 있는 영수증 사진은 여행 사진과 영수증 묶음에 함께 들어, 돌아올 칸을 섹션까지 가려 찾는다
/// (`CategoryView` 의 `GridCellID` 와 같은 모양).
private struct TripCellID: Hashable {
  let section: Int
  let image: ImageAsset.ID
}
