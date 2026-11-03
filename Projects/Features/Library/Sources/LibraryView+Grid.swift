import Core
import DesignSystem
import SwiftUI

// MARK: - 카테고리 카드 격자

extension LibraryView {
  /// 카테고리 카드 격자. 위에서부터 인덱싱 → 곧 만료 띠 → 알림 안내 → 빈 상태 또는 정리 도우미 → 캡처 → 사진 → 기타 → 개인정보 처리방침 링크.
  /// 검색 중에는 `SearchResultsView` 가 대신 보인다.
  /// `isRevealed` 는 이 화면 인스턴스에서 카드가 처음 생길 때 한 번 참이 된다(`LibraryView.hasRevealedCards`). 그때 정리 도우미 카드와
  /// 카테고리 카드가 보이는 순서대로 떠오른다(`snapReveal`). 그 뒤 새로 생기는 카드(분류 중 새 카테고리, 상세에서 돌아옴, LazyVStack 이 다시 만듦)는
  /// 이미 참이라 바로 보인다.
  /// 분류 완료 축하 카드는 축하 id 가 바뀔 때만 애니메이션해(진행 카드 사이 전환 같은 다른 변화는 그대로) 아래 카드들이 함께 내려가고 올라온다.
  /// 축하가 나타날 때 성공 햅틱을 한 번 내고(사라질 때는 없음), 2.5초 뒤 접히는 카드를 찾아가기 어려워 VoiceOver 로 알린다.
  /// 다른 화면(push)이나 검색을 보는 동안 축하가 생기면 카드는 보이지 않은 채 접힌다. 검색 중이면 이 격자가 계층에 없어 햅틱도 없다.
  /// 곧 만료 띠(`LibraryView+ExpiringStrip.swift`)는 숨김 ↔ 보임이 바뀔 때만 애니메이션해 위에서 내려오며 나타나고(아래 카드들이 함께 내려감)
  /// 같은 길로 접힌다(동작 줄이기면 투명도만). 칩이 하나 빠지거나 더해지는 변화는 바로 바뀐다.
  func homeGrid(isRevealed: Bool) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        self.indexingSection
        // 만료 알림 받기 안내가 바로 아래에 와 같은 주제끼리 붙는다.
        self.expiringStripSection
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
            .snapReveal(isRevealed, index: 0)
        }
        self.categorySection("캡처", group: .information, isRevealed: isRevealed)
        self.categorySection("사진", group: .photo, isRevealed: isRevealed)
        self.categorySection("기타", group: .other, isRevealed: isRevealed)
        // 앱 안 처리방침 링크(심사 가이드라인 5.1.1(i)). 온보딩은 권한을 허용하면 다시 볼 수 없어 여기에도 둔다.
        PrivacyPolicyLink()
          .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
      .animation(self.celebrationAnimation, value: self.model.indexingCelebration?.id)
      .animation(self.expiringStripAnimation, value: self.showsExpiringStrip)
    }
    .sensoryFeedback(trigger: self.model.indexingCelebration?.id) { _, new in
      new == nil ? nil : .success
    }
    .onChange(of: self.model.indexingCelebration?.id) { _, id in
      if id != nil {
        AccessibilityNotification.Announcement("분류를 마쳤습니다").post()
      }
    }
  }

  /// 카드가 떠오르는 순서. 정리 도우미 카드가 0 이고, 이어서 보이는 순서대로(캡처 → 사진(여행 먼저) → 기타 섹션, 섹션 안은 `ImageCategory.allCases` 순서).
  private func revealIndex(of category: ImageCategory) -> Int {
    let order = [ImageCategoryGroup.information, .photo, .other].flatMap { group in
      let categories = ImageCategory.allCases.filter { $0.group == group && self.model.categoryCounts[$0] != nil }
      return categories.filter { $0 == .travel } + categories.filter { $0 != .travel }
    }
    return 1 + (order.firstIndex(of: category) ?? 0)
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

  /// 분류된 카테고리가 없을 때의 카드. 분류 중이면 이미지 수와 분류 중임을, 아니면 사진이 들어오면 나눠 둔다고 알린다.
  private var emptyCard: some View {
    StatusMessageView(
      empty: self.model.isIndexing ? "이미지 \(self.model.imageCount)장" : "아직 나눌 사진이 없어요",
      description: self.emptyDescription
    )
    .frame(maxWidth: .infinity)
    .snapCard()
  }

  private var emptyDescription: String {
    if self.model.isIndexing {
      "이미지를 분류하는 중이에요."
    } else {
      "사진이 들어오면 알아서 나눠 둘게요."
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
    }
    .buttonStyle(.snapCard)
    .accessibilityElement(children: .combine)
  }

  /// 이미지가 있는 카테고리만 카드로 보여 주고, 하나도 없으면 섹션째 숨긴다. 기프티콘 카드는 기프티콘 목록, 영수증 카드는 영수증 목록,
  /// 여행 카드는 여행 폴더 목록을 연다. 여행 카드는 "사진" 섹션 격자 위에 가로 전체로 따로 둔다.
  @ViewBuilder
  private func categorySection(_ title: String, group: ImageCategoryGroup, isRevealed: Bool) -> some View {
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
          self.card(travel.category, count: travel.count, isWide: true, titleLines: .unlimited, isRevealed: isRevealed)
          // 여행은 고른 사진만으로 판정하므로 제한 접근이면 실제 여행과 다를 수 있다 (docs/ARCHITECTURE.md §4 여행 판정).
          if self.model.isLimited {
            self.footnote("선택한 사진만으로 여행을 찾아 정확하지 않을 수 있습니다.")
          }
        }
        let gridRows = rows.filter { $0.category != .travel }
        if !gridRows.isEmpty {
          LazyVGrid(columns: self.columns, spacing: 12) {
            ForEach(gridRows, id: \.category) { row in
              self.card(
                row.category,
                count: row.count,
                isWide: self.isSingleColumn,
                titleLines: self.gridTitleLines,
                isRevealed: isRevealed
              )
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
    titleLines: LibraryCategoryCard.TitleLines,
    isRevealed: Bool
  ) -> some View {
    LibraryCategoryCard(
      category: category,
      count: count,
      ids: self.model.coverIDs[category] ?? [],
      coverModel: self.coverModel,
      isWide: isWide,
      titleLines: titleLines,
      zoomNamespace: self.zoomNamespace
    )
    .snapReveal(isRevealed, index: self.revealIndex(of: category))
  }

  private func footnote(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}
