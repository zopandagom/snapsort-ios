import Core
import DesignSystem
import SwiftUI

/// 기프티콘 목록: 미사용/사용함 탭과 만료 임박순/월별 정렬 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 만료 임박순은 남은 것(가까운 날부터) → 만료됨(최근 만료부터) → 만료일 모름 → 확인 중 섹션이고, 월별은 생성일의 연·월 섹션이다.
/// 탭·정렬은 저장하지 않는 화면 일시 상태라 이 View 가 갖는다: 새로 열면 기본값, 상세에서 돌아오면 그대로다.
/// 줄을 누르면 사진 상세로 가고, 그 상세만 기프티콘 정보·사용함 버튼·바코드를 보인다.
/// 썸네일은 카테고리 화면과 같은 보관 규칙을 쓰도록 `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(category:)`).
public struct GifticonListView: View {
  let model: GifticonListModel
  let categoryModel: CategoryModel

  @State private var tab: GifticonTab = .unused
  @State private var sort: GifticonSort = .expiry

  public init(model: GifticonListModel, categoryModel: CategoryModel) {
    self.model = model
    self.categoryModel = categoryModel
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .top) {
        Picker("보기", selection: self.$tab) {
          Text("미사용").tag(GifticonTab.unused)
          Text("사용함").tag(GifticonTab.used)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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
          }
        }
      }
      .task { await self.model.onAppear() }
      .task { await self.categoryModel.thumbnailScreenAppeared(category: .gifticon) }
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.model.content {
    case .loading:
      ProgressView()
    case .failed:
      StatusMessageView("기프티콘을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    case let .loaded(items):
      let sections = GifticonListSections.sections(
        of: items,
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
        ProgressView()
      } else {
        self.list(sections)
      }
    }
  }

  private func list(_ sections: GifticonListSections) -> some View {
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

  private func rows(_ items: [GifticonListItem]) -> some View {
    ForEach(items) { item in
      NavigationLink(value: PhotoDetailRoute(asset: item.asset, gifticon: item)) {
        GifticonRow(
          categoryModel: self.categoryModel,
          item: item,
          today: self.model.today,
          calendar: self.model.calendar
        )
      }
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

/// 기프티콘 한 줄: 썸네일·교환처·만료일·D-n. 모델이 채운 값에는 "추정"을 붙인다.
struct GifticonRow: View {
  let categoryModel: CategoryModel
  let item: GifticonListItem
  let today: LocalDate
  let calendar: Calendar

  var body: some View {
    HStack(spacing: 12) {
      CategoryThumbnailCell(model: self.categoryModel, asset: self.item.asset, category: .gifticon)
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
      switch self.item.status {
      case .checking:
        Text("확인 중")
          .foregroundStyle(.secondary)
        Spacer()
      case let .extracted(info):
        VStack(alignment: .leading, spacing: 4) {
          GifticonFieldText(
            info.redemptionPlace.map { Text($0) } ?? Text("교환처 모름"),
            isKnown: info.redemptionPlace != nil,
            isEstimated: self.item.estimatedFields.contains(.redemptionPlace)
          )
          .font(.body)
          GifticonFieldText(
            info.expiryDate.map { GifticonExpiryText.date($0, calendar: self.calendar) } ?? Text("만료일 모름"),
            isKnown: info.expiryDate != nil,
            isEstimated: self.item.estimatedFields.contains(.expiryDate)
          )
          .font(.subheadline)
        }
        Spacer()
        if let expiryDate = info.expiryDate {
          GifticonDueBadge(due: GifticonDue(expiryDate: expiryDate, today: self.today))
        }
      }
    }
  }
}

/// 필드 값 한 줄. 모르는 값은 흐리게, 모델이 채운 값에는 "추정" 캡슐을 붙인다.
struct GifticonFieldText: View {
  let text: Text
  let isKnown: Bool
  let isEstimated: Bool

  init(_ text: Text, isKnown: Bool, isEstimated: Bool) {
    self.text = text
    self.isKnown = isKnown
    self.isEstimated = isEstimated
  }

  var body: some View {
    HStack(spacing: 6) {
      self.text
        .foregroundStyle(self.isKnown ? .primary : .secondary)
        .lineLimit(1)
      if self.isEstimated {
        EstimatedBadge()
      }
    }
  }
}

/// 언어 모델이 채운 값(또는 출처를 아직 모르는 옛 값) 표시.
struct EstimatedBadge: View {
  var body: some View {
    Text("추정")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .foregroundStyle(SnapColor.lilacText)
      .background(SnapColor.lilacSoft, in: .capsule)
      .accessibilityLabel(Text("추정한 값"))
  }
}

/// D-n 배지: 오늘 만료는 "D-day", 남으면 "D-3", 지나면 "3일 지남".
struct GifticonDueBadge: View {
  let due: GifticonDue

  var body: some View {
    Text(self.title)
      .font(.subheadline.weight(.semibold).monospacedDigit())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(self.style.text)
      .background(self.style.fill, in: .capsule)
  }

  private var title: String {
    switch self.due {
    case .remaining(days: 0): "D-day"
    case let .remaining(days): "D-\(days)"
    case let .expired(daysAgo): "\(daysAgo)일 지남"
    }
  }

  /// 7일 안이면 채운 강조색, 남으면 블러시, 지나면 중립 면. 모두 글자 대비 4.5:1 이상이다(`SnapColorTests`).
  private var style: (text: ColorToken, fill: ColorToken) {
    switch self.due {
    case let .remaining(days) where days <= 7: (SnapColor.onAccent, SnapColor.accent)
    case .remaining: (SnapColor.accent, SnapColor.blush)
    case .expired: (SnapColor.inkSecondary, SnapColor.neutral)
    }
  }
}

enum GifticonExpiryText {
  /// 만료일을 기기 달력·시간대로 쓴다. 표시 시각은 그날 정오다(자정이 없는 시간대 전환일에도 날짜가 밀리지 않고,
  /// 시간대가 바뀐 직후 한 프레임 동안 달력 사본이 옛 시간대여도 12시간 미만 차이면 같은 날짜가 보인다). 자정으로 바꾸지 않는다.
  /// 형식에도 같은 달력·시간대를 써서 Model 의 `calendar` 와 같은 날짜를 보인다.
  static func date(_ date: LocalDate, calendar: Calendar) -> Text {
    guard let noon = date.noon(in: calendar) else {
      return Text(verbatim: String(format: "%04d-%02d-%02d", date.year, date.month, date.day))
    }
    var style = Date.FormatStyle.dateTime.year().month().day()
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    return Text(noon, format: style)
  }
}

extension GifticonExpirySection.Kind {
  var title: String {
    switch self {
    case .remaining: "남은 기프티콘"
    case .expired: "만료됨"
    case .unknownExpiry: "만료일 모름"
    case .checking: "확인 중"
    }
  }
}

extension GifticonListSections {
  var isEmpty: Bool {
    switch self {
    case let .byExpiry(sections): sections.isEmpty
    case let .byMonth(sections): sections.isEmpty
    }
  }
}
