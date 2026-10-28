import Core
import DesignSystem
import SwiftUI

/// 보관함 검색 결과 (docs/ARCHITECTURE.md §4 검색). 보관함 화면의 NavigationStack 루트 내용으로, 검색 중에는 카테고리 카드 대신 보인다.
/// 위에서부터 이름이 맞은 카테고리 줄(카테고리 화면·각 목록으로), 캐시된 장소 이름이 맞은 여행 줄(여행 폴더 상세로),
/// 사진 줄(최신순, 맞은 곳 한 줄. 주소·번호 행동만 있는 사진 상세로)이다.
/// 썸네일은 카테고리 화면과 같은 보관 규칙을 쓰도록 `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(scope: .search)`).
/// 검색어와 맞은 줄(OCR 텍스트)은 화면에만 보이고 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
struct SearchResultsView: View {
  let model: SearchModel
  let categoryModel: CategoryModel
  let isLimited: Bool

  var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // 분기마다가 아니라 바깥 하나에 둬, 분기가 바뀔 때 다시 읽기 루프와 썸네일 범위가 끊겼다 다시 시작하지 않게 한다.
      .task { await self.model.onAppear() }
      .task { await self.categoryModel.thumbnailScreenAppeared(scope: .search) }
  }

  @ViewBuilder
  private var contentView: some View {
    if self.model.loadState == .unavailable {
      StatusMessageView(
        "검색할 수 없습니다",
        systemImage: "magnifyingglass",
        description: "분류 결과를 열지 못했습니다."
      )
    } else if self.model.loadState == .failed {
      // 검색어가 없어도 실패 화면이다. 안내만 보이면 입력해도 결과가 안 나오는 이유를 모른다.
      StatusMessageView("검색을 준비하지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    } else if !self.model.hasQuery {
      SnapList {
        Section {
          Text("사진 속 글자, 쇼핑몰·브랜드·대화 앱·지역, 카테고리, 여행 장소 이름으로 찾습니다.")
            .foregroundStyle(.secondary)
        }
        self.notices
      }
    } else if let results = self.model.results {
      if results.isEmpty {
        SnapList {
          Section {
            ContentUnavailableView.search(text: results.query)
          }
          self.notices
        }
      } else if self.categoryModel.thumbnailScope != .search {
        // 다른 화면의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 줄을 그린다(`CategoryView.content` 와 같은 이유).
        ProgressView()
      } else {
        self.list(results)
      }
    } else {
      ProgressView()
    }
  }

  private func list(_ results: SearchResults) -> some View {
    SnapList {
      if !results.categories.isEmpty {
        Section("카테고리") {
          ForEach(results.categories) { hit in
            NavigationLink(value: hit.category) {
              LabeledContent {
                Text(hit.category.countText(hit.count))
              } label: {
                CategoryLabel(category: hit.category)
              }
            }
          }
        }
      }
      if !results.trips.isEmpty {
        Section("여행") {
          ForEach(results.trips) { hit in
            NavigationLink(value: TripFolderRoute(trip: hit.trip)) {
              self.tripRow(hit)
            }
          }
        }
      }
      if !results.images.isEmpty {
        Section("사진 \(results.images.count)장") {
          ForEach(results.images) { hit in
            NavigationLink(value: PhotoDetailRoute(asset: hit.asset)) {
              SearchImageRow(categoryModel: self.categoryModel, hit: hit, calendar: self.model.calendar)
            }
          }
        }
      }
      self.notices
    }
  }

  /// 여행 폴더 목록 줄과 같은 표시: 장소 이름과 기간·사진 수.
  private func tripRow(_ hit: SearchTripHit) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(hit.placeName)
        .lineLimit(1)
      Text("\(TripPeriodText.text(hit.period, calendar: self.model.calendar)) · 사진 \(hit.trip.assetIDs.count)장")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  /// 아직 검색되지 않는 사진과 제한 접근 안내. 돌아가는 표시 없이 정적 문구다.
  @ViewBuilder
  private var notices: some View {
    let showsPending = self.model.loadState == .loaded && self.model.pendingTextCount > 0
    if showsPending || self.isLimited {
      Section {
        if showsPending {
          Text("글자를 아직 읽지 않은 \(self.model.pendingTextCount)장은 검색되지 않습니다. iCloud 에만 있는 사진은 기기에 내려받은 뒤 읽습니다.")
        }
        if self.isLimited {
          Text("선택한 사진에서만 찾습니다.")
        }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }
}

/// 사진 줄: 썸네일·날짜·맞은 곳 한 줄. 맞은 곳은 OCR 줄 원문이거나 묶음 값의 이름이다.
private struct SearchImageRow: View {
  let categoryModel: CategoryModel
  let hit: SearchHit
  let calendar: Calendar

  var body: some View {
    HStack(spacing: 12) {
      CategoryThumbnailCell(model: self.categoryModel, asset: self.hit.asset, scope: .search)
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
        // 썸네일 설명에도 날짜가 있어 줄의 날짜가 두 번 읽히지 않게 한다.
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        self.dateText
          .font(.subheadline)
        Text(self.matchedText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
  }

  private var dateText: Text {
    guard let date = self.hit.asset.creationDate else { return Text("날짜 없음") }
    return Text(date, format: ReceiptDateText.dayStyle(calendar: self.calendar))
  }

  private var matchedText: String {
    switch self.hit.match {
    case let .line(line): line
    case let .group(title): title
    }
  }
}
