import Core
import DesignSystem
import SwiftUI

// MARK: - 카테고리 카드 격자

extension LibraryView {
  /// 카테고리 카드 격자. 위에서부터 인덱싱 → 알림 안내 → 빈 상태 또는 정리 도우미 → 캡처 → 사진 → 기타.
  /// 검색 중에는 `SearchResultsView` 가 대신 보인다.
  var homeGrid: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        self.indexingSection
        if self.model.showsExpiryReminderButton {
          self.expiryReminderSection
        }
        if self.model.showsNotificationSettingsButton {
          self.notificationSettingsSection
        }
        // 덮는 overlay 로 두면 위의 진행률·다시 시도를 가리므로 격자 안에 둔다.
        if self.model.categoryCounts.isEmpty {
          self.emptyCard
        } else {
          self.cleanupCard
        }
        self.categorySection("캡처", group: .information)
        self.categorySection("사진", group: .photo)
        self.categorySection("기타", group: .other)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
  }

  /// 큰 글씨(접근성 크기)에서는 1열로 둬 이름이 잘리지 않게 한다.
  private var isSingleColumn: Bool {
    self.dynamicTypeSize.isAccessibilitySize
  }

  private var columns: [GridItem] {
    let count = self.isSingleColumn ? 1 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
  }

  /// 2열은 기본~`.large` 에서 한 줄, `.xLarge` 이상에서 두 줄 자리를 잡아 같은 행 카드 높이를 맞춘다. 1열은 제한하지 않는다.
  private var gridTitleLines: LibraryCategoryCard.TitleLines {
    if self.isSingleColumn {
      .unlimited
    } else if self.dynamicTypeSize >= .xLarge {
      .double
    } else {
      .single
    }
  }

  private var emptyCard: some View {
    ContentUnavailableView(
      "이미지 \(self.model.imageCount)장",
      systemImage: "photo.stack",
      description: Text(self.emptyDescription)
    )
    .frame(maxWidth: .infinity)
    .snapCard()
  }

  private var emptyDescription: String {
    if self.model.isIndexing {
      "이미지를 분류하는 중입니다."
    } else {
      "분류된 이미지가 없습니다."
    }
  }

  /// 이미지가 하나라도 분류돼 있을 때만 보인다. 정리 화면은 그 안에서 후보를 고른다.
  private var cleanupCard: some View {
    NavigationLink(value: CleanupRoute.cleanup) {
      HStack(spacing: 12) {
        Image(systemName: "sparkles")
          .font(.title2)
          .foregroundStyle(SnapColor.rose)
        VStack(alignment: .leading, spacing: 2) {
          Text("정리 도우미")
            .font(.headline)
          Text("지난 기프티콘·비슷한 사진 정리")
            .font(.footnote)
            .foregroundStyle(SnapColor.accent)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .foregroundStyle(SnapColor.accent)
      }
      .snapCard(SnapColor.blush)
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
  }

  /// 이미지가 있는 카테고리만 카드로 보여 주고, 하나도 없으면 섹션째 숨긴다. 기프티콘 카드는 기프티콘 목록, 영수증 카드는 영수증 목록,
  /// 여행 카드는 여행 폴더 목록을 연다. 여행 카드는 "사진" 섹션 격자 위에 가로 전체로 따로 둔다.
  @ViewBuilder
  private func categorySection(_ title: String, group: ImageCategoryGroup) -> some View {
    let rows = ImageCategory.allCases.compactMap { category in
      self.model.categoryCounts[category].map { (category: category, count: $0) }
    }
    .filter { $0.category.group == group }
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.title3.bold())
          .accessibilityAddTraits(.isHeader)
        if let travel = rows.first(where: { $0.category == .travel }) {
          self.card(travel.category, count: travel.count, isWide: true, titleLines: .unlimited)
          // 여행은 고른 사진만으로 판정하므로 제한 접근이면 실제 여행과 다를 수 있다 (docs/ARCHITECTURE.md §4 여행 판정).
          if self.model.isLimited {
            self.footnote("선택한 사진만으로 여행을 찾아 정확하지 않을 수 있습니다.")
          }
        }
        let gridRows = rows.filter { $0.category != .travel }
        if !gridRows.isEmpty {
          LazyVGrid(columns: self.columns, spacing: 12) {
            ForEach(gridRows, id: \.category) { row in
              self.card(row.category, count: row.count, isWide: self.isSingleColumn, titleLines: self.gridTitleLines)
            }
          }
        }
        // 정보형 카테고리는 2단계에서 글자를 읽으며 더해진다 (docs/ARCHITECTURE.md §4 인덱싱).
        if group == .information, self.model.isIndexing, self.model.indexingProgress?.phase == .recognizingText {
          self.footnote("글자를 읽는 중이라 개수가 늘어날 수 있습니다.")
        }
      }
    }
  }

  private func card(
    _ category: ImageCategory,
    count: Int,
    isWide: Bool,
    titleLines: LibraryCategoryCard.TitleLines
  ) -> some View {
    LibraryCategoryCard(
      category: category,
      count: count,
      ids: self.model.coverIDs[category] ?? [],
      coverModel: self.coverModel,
      isWide: isWide,
      titleLines: titleLines
    )
  }

  private func footnote(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}
