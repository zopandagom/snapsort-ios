import Core
import DesignSystem
import SwiftUI

/// 기프티콘 목록: 미사용/사용함 탭(DesignSystem `SnapSegmentedTabs`, 탭별 개수)과 만료 임박순/월별 정렬 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 만료 임박순은 남은 것(가까운 날부터) → 만료됨(최근 만료부터) → 만료일 모름 → 확인 중 섹션이고, 월별은 생성일의 연·월 섹션이다.
/// 탭·정렬은 저장하지 않는 화면 일시 상태라 이 View 가 갖는다: 새로 열면 기본값, 상세에서 돌아오면 그대로이고
/// 상세에서 마지막으로 본 줄이 보이게 한 번 스크롤한다(`CategoryModel.detailReturn`).
/// 탭을 바꾸면 목록이 탭 방향으로 밀려 바뀌고 새 목록은 맨 위부터 보인다.
/// 줄을 누르면 사진 상세로 가고, 그 상세만 기프티콘 정보·사용함 버튼·바코드를 보인다. 상세는 누른 줄의 섹션 안에서 넘긴다.
/// 줄 오른쪽 버튼을 누르거나 줄을 왼쪽으로 밀면 "사용함"(사용함 탭은 "미사용으로")으로 바로 바꾼다. 성공하면 그 줄은 잠깐 옛 탭에 남아 도장·색 빠짐(사용함으로 옮길 때)
/// 뒤 빠지고 탭 숫자가 바뀐다(`GifticonUsageLingerState`). 실패하면 알리고 줄은 그대로다.
/// 썸네일은 카테고리 화면과 같은 보관 규칙을 쓰도록 `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(category:)`).
public struct GifticonListView: View {
  let model: GifticonListModel
  let categoryModel: CategoryModel

  @State private var tab: GifticonTab = .unused
  @State private var sort: GifticonSort = .expiry
  /// 이 화면 인스턴스의 방문 값. 사진 상세에서 돌아오면 같은 값이라 돌아올 위치가 이 화면 것인지 가른다.
  @State private var visit = UUID()
  /// 줄 버튼·줄 밀기로 바꾼 줄이 옛 탭에 머무는 상태. 이 화면이 생긴 뒤의 변경만 다룬다.
  @State private var usage: GifticonUsageLingerState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(model: GifticonListModel, categoryModel: CategoryModel) {
    self.model = model
    self.categoryModel = categoryModel
    self._usage = State(initialValue: GifticonUsageLingerState(baselineSequence: model.usageRevision))
  }

  public var body: some View {
    ZStack {
      self.contentView
        .id(self.tab)
        .transition(self.tabTransition)
    }
    // `.clipped()` 로 자르면 처음 열 때 큰 제목이 그려지지 않는다(탭을 바꿔야 보인다). 전환은 가로로만 움직여 화면 가장자리에서 잘리므로 자르지 않는다.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .safeAreaInset(edge: .top) {
      SnapSegmentedTabs(selection: self.$tab, tabs: [
        .init(.unused, "미사용", count: self.displayItems.map { items in items.count { !$0.isUsed } }),
        .init(.used, "사용함", count: self.displayItems.map { items in items.count(where: \.isUsed) }),
      ])
      .padding(.horizontal)
      .padding(.vertical, 8)
      // 바 재질이 위쪽 안전 영역까지 번져 큰 제목을 덮지 않게(처음 열 때 제목이 흐려 보이던 원인) 탭 자리만 칠한다.
      .background(.bar, ignoresSafeAreaEdges: [])
    }
    .navigationTitle(ImageCategory.gifticon.title)
    .snapScreenBackground()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("정렬", selection: self.$sort) {
            Text("만료 임박순").tag(GifticonSort.expiry)
            Text("월별").tag(GifticonSort.month)
          }
        } label: {
          Label("정렬", systemImage: "arrow.up.arrow.down")
            // 루트 `snapTheme()` 의 본문 글자색을 물려받으면 유리 툴바 Menu 가 흰색으로 그린다.
            .foregroundStyle(.tint)
        }
      }
    }
    .task { await self.model.onAppear() }
    .task { await self.categoryModel.thumbnailScreenAppeared(category: .gifticon) }
    .onChange(of: self.model.usageChanges, initial: true) { _, changes in
      self.scheduleLingering(changes)
    }
    .sensoryFeedback(.success, trigger: self.model.usageRevision)
    .alert(
      self.model.alert?.title ?? "",
      isPresented: Binding(
        get: { self.model.alert != nil },
        set: { isPresented in
          if !isPresented {
            self.model.alertDismissed()
          }
        }
      ),
      presenting: self.model.alert
    ) { _ in
      Button("확인", role: .cancel) {}
    } message: { alert in
      Text(alert.message)
    }
  }

  /// 미사용은 늘 왼쪽, 사용함은 늘 오른쪽에서 들고 난다. 동작 줄이기면 투명도만 바꾼다.
  private var tabTransition: AnyTransition {
    if self.reduceMotion {
      return .opacity
    }
    return .move(edge: self.tab == .unused ? .leading : .trailing).combined(with: .opacity)
  }

  /// 머무는 줄을 반영한 목록. 읽기 전·실패면 nil.
  private var displayItems: [GifticonListItem]? {
    guard case let .loaded(items) = self.model.content else { return nil }
    return self.usage.displayItems(items, changes: self.model.usageChanges)
  }

  /// 새로 성공한 쓰기마다 VoiceOver 로 알리고, 도장·색 빠짐을 보인 뒤 줄을 빼고 옛 탭에서 거둔다. 줄마다 따로 돈다.
  /// View 상태만 바꾸므로 화면이 사라지면 함께 사라진다.
  private func scheduleLingering(_ changes: [ImageAsset.ID: GifticonUsageChange]) {
    for change in self.usage.scheduleNew(changes) {
      AccessibilityNotification.Announcement(change.isUsed ? "사용함으로 옮겼습니다" : "미사용으로 옮겼습니다").post()
      let sequence = change.sequence
      Task { @MainActor in
        try? await Task.sleep(for: SnapStamp.settle)
        withAnimation(SnapStamp.exitAnimation) {
          self.usage.exit(sequence)
        }
        try? await Task.sleep(for: SnapStamp.exitDuration)
        withAnimation(.snappy) {
          self.usage.settle(sequence)
        }
      }
    }
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.model.content {
    case .loading:
      SnapLoadingDots()
    case .failed:
      StatusMessageView("기프티콘을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    case let .loaded(items):
      let sections = GifticonListSections.sections(
        of: self.usage.displayItems(items, changes: self.model.usageChanges),
        used: self.tab == .used,
        sort: self.sort,
        today: self.model.today,
        calendar: self.model.calendar
      )
      if sections.isEmpty {
        StatusMessageView(
          self.tab == .unused ? "사용하지 않은 기프티콘이 없습니다" : "사용한 기프티콘이 없습니다",
          glyph: ImageCategory.gifticon.glyph
        )
      } else if self.categoryModel.category != .gifticon {
        // 지난 카테고리의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 줄을 그린다(`CategoryView.content` 와 같은 이유).
        SnapLoadingDots()
      } else {
        self.list(sections)
      }
    }
  }

  private func list(_ sections: GifticonListSections) -> some View {
    ScrollViewReader { proxy in
      self.listContent(sections)
        // 상세에서 돌아와 다시 보일 때 이 방문의 돌아올 위치가 있으면 그 줄이 보이게 한 번 스크롤한다(이미 보이면 움직이지 않고,
        // 지금 탭·정렬의 목록에 없으면 아무것도 하지 않는다).
        .onAppear {
          guard let target = self.categoryModel.detailReturn, target.origin.visit == self.visit else { return }
          self.categoryModel.detailReturnApplied(visit: self.visit)
          proxy.scrollTo(target.id, anchor: nil)
        }
    }
  }

  private func listContent(_ sections: GifticonListSections) -> some View {
    SnapList {
      switch sections {
      case let .byExpiry(sections):
        ForEach(sections) { section in
          Section {
            self.rows(section.items)
          } header: {
            Text(section.kind.title)
          } footer: {
            if section.kind == .checking {
              Text("글자를 읽으면 만료일을 찾습니다. iCloud 에만 있는 사진은 기기에 내려받은 뒤 확인합니다.")
            }
          }
        }
      case let .byMonth(sections):
        ForEach(sections) { section in
          Section {
            self.rows(section.items)
          } header: {
            self.monthHeader(section)
          }
        }
      }
    }
  }

  /// 상세는 이 섹션의 줄들을 보이는 순서대로 넘긴다.
  private func rows(_ items: [GifticonListItem]) -> some View {
    let pages = PhotoPages.pages(gifticons: items)
    let origin = PhotoDetailOrigin(visit: self.visit, section: 0)
    return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
      let linger = self.usage.linger(for: item.id, changes: self.model.usageChanges)
      let isExiting = linger?.isExiting ?? false
      // 버튼은 상세로 가는 링크 밖 옆에 둬, 버튼을 누르면 상세가 열리지 않고 나머지 자리를 누르면 열린다(정리 화면 체크 원과 같은 배치).
      HStack(spacing: 8) {
        NavigationLink(value: PhotoDetailRoute(pages: pages, index: index, origin: origin)) {
          GifticonRow(
            categoryModel: self.categoryModel,
            item: item,
            today: self.model.today,
            calendar: self.model.calendar,
            isStamped: linger?.isStamped ?? false
          )
        }
        // 링크가 버튼 앞까지만이라 시스템 화살표가 줄 끝이 아니라 버튼 바로 왼쪽에 그려진다. 시안처럼 숨기고 버튼을 줄 끝에 둔다.
        .navigationLinkIndicatorVisibility(.hidden)
        .environment(\.photoDetailOrigin, origin)
        // 머무는 줄·쓰는 중인 줄은 자리를 지킨 채 막아 두 번 쓰지 않는다(줄 모양이 흔들리지 않게 숨기지 않는다).
        self.usageRowButton(item)
          .disabled(linger != nil || self.model.updatingUsageIDs.contains(item.id))
      }
      .opacity(isExiting ? 0 : 1)
      .offset(x: isExiting && !self.reduceMotion ? -SnapStamp.exitOffset : 0)
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        // 머무는 줄·쓰는 중인 줄은 단추를 두지 않아 두 번 쓰지 않는다.
        if linger == nil, !self.model.updatingUsageIDs.contains(item.id) {
          self.usageSwipeButton(item)
        }
      }
    }
  }

  /// 줄 오른쪽 버튼. 미사용 탭은 "사용함", 사용함 탭은 "미사용으로"(줄 밀기와 같은 이벤트). 접근성 이름에 교환처를 붙여 어느 줄인지 읽는다.
  private func usageRowButton(_ item: GifticonListItem) -> some View {
    Button(item.isUsed ? "미사용으로" : "사용함") {
      Task { await self.model.usageToggled(id: item.id, toUsed: !item.isUsed) }
    }
    .buttonStyle(.snapSecondary)
    .controlSize(.small)
    .font(.subheadline.weight(.semibold))
    .fixedSize()
    .accessibilityLabel(Text(self.usageButtonAccessibilityLabel(item)))
  }

  private func usageButtonAccessibilityLabel(_ item: GifticonListItem) -> String {
    let action = item.isUsed ? "미사용으로 되돌리기" : "사용함으로 표시"
    guard case let .extracted(info) = item.status, let place = info.redemptionPlace else { return action }
    return "\(place), \(action)"
  }

  /// 시스템이 tint 면 위에 흰 글자·아이콘으로 그리므로, 두 모드 모두 흰 글자 대비를 맞춘 tint 를 쓴다.
  @ViewBuilder
  private func usageSwipeButton(_ item: GifticonListItem) -> some View {
    if item.isUsed {
      Button("미사용으로", systemImage: "arrow.uturn.backward") {
        Task { await self.model.usageToggled(id: item.id, toUsed: false) }
      }
      .tint(SnapColor.swipeRestore)
    } else {
      Button("사용함", systemImage: "checkmark.seal") {
        Task { await self.model.usageToggled(id: item.id, toUsed: true) }
      }
      .tint(SnapColor.swipeUse)
    }
  }

  /// 카테고리 화면 머리(`CategoryView.header`)와 같은 형식.
  @ViewBuilder
  private func monthHeader(_ section: GifticonMonthSection) -> some View {
    if section.month != nil, let date = section.items.first?.asset.creationDate {
      Text(date, format: .dateTime.year().month(.wide))
    } else {
      Text("날짜 없음")
    }
  }
}

extension GifticonListAlert {
  var title: String {
    switch self {
    case .usageUpdateFailed: "사용 여부를 저장하지 못했습니다"
    }
  }

  var message: String {
    switch self {
    case .usageUpdateFailed: "잠시 뒤 다시 시도해 주세요."
    }
  }
}
