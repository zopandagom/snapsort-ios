import Core
import DesignSystem
import SwiftUI

/// 영수증 목록: 월별/가게별 묶음과 섹션별 통화별 합계 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 월별은 생성일의 연·월 섹션(최신 달부터, 날짜 없음은 맨 뒤)이고, 가게별은 가장 최근 영수증이 있는 가게부터, 가게 모름 → 확인 중이 맨 뒤다.
/// 섹션 머리 합계는 통화마다 따로 더하고(섞어 더하지 않는다), 금액 모름·확인 중 수를 함께 쓴다. 취소 전표는 합계에 넣지 않는다.
/// 묶기는 저장하지 않는 화면 일시 상태라 이 View 가 갖는다: 새로 열면 월별, 상세에서 돌아오면 그대로다.
/// 줄을 누르면 사진 상세로 간다(주소·번호 행동만). 썸네일은 카테고리 화면과 같은 보관 규칙을 쓰도록
/// `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(category:)`).
/// 가게·금액은 사진에서 읽은 텍스트라 화면에만 보이고 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct ReceiptListView: View {
  let model: ReceiptListModel
  let categoryModel: CategoryModel

  @State private var grouping: ReceiptGrouping = .month

  public init(model: ReceiptListModel, categoryModel: CategoryModel) {
    self.model = model
    self.categoryModel = categoryModel
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(ImageCategory.receipt.title)
      .snapScreenBackground()
      // 위쪽 inset 막대를 두지 않고 툴바 메뉴로 고른다(큰 제목이 처음부터 선명하게).
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Picker("묶기", selection: self.$grouping) {
              Text("월별").tag(ReceiptGrouping.month)
              Text("가게별").tag(ReceiptGrouping.store)
            }
          } label: {
            Label("묶기", systemImage: "rectangle.3.group")
              // 루트 `snapTheme()` 의 본문 글자색을 물려받으면 유리 툴바 Menu 가 흰색으로 그린다.
              .foregroundStyle(.tint)
          }
        }
      }
      .task { await self.model.onAppear() }
      .task { await self.categoryModel.thumbnailScreenAppeared(category: .receipt) }
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.model.content {
    case .loading:
      SnapLoadingDots()
    case .failed:
      StatusMessageView("영수증을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
        self.model.retryButtonTapped()
      }
    case let .loaded(items):
      let sections = ReceiptListSections.sections(of: items, grouping: self.grouping, calendar: self.model.calendar)
      if sections.isEmpty {
        StatusMessageView("영수증이 없습니다", glyph: ImageCategory.receipt.glyph)
      } else if self.categoryModel.category != .receipt {
        // 지난 카테고리의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 줄을 그린다(`CategoryView.content` 와 같은 이유).
        SnapLoadingDots()
      } else {
        self.list(sections)
      }
    }
  }

  private func list(_ sections: ReceiptListSections) -> some View {
    SnapList {
      switch sections {
      case let .byMonth(sections):
        ForEach(sections) { section in
          Section {
            self.rows(section.items)
          } header: {
            ReceiptSectionHeader(title: self.monthTitle(section), totals: section.totals)
          } footer: {
            if section.totals.checkingCount > 0 {
              ReceiptCheckingFooter()
            }
          }
        }
      case let .byStore(sections):
        ForEach(sections) { section in
          Section {
            self.rows(section.items)
          } header: {
            ReceiptSectionHeader(
              title: Text(verbatim: "\(self.storeTitle(section)) · \(section.items.count)장"),
              totals: section.kind == .checking ? nil : section.totals
            )
          } footer: {
            if section.kind == .checking {
              ReceiptCheckingFooter()
            }
          }
        }
      }
    }
  }

  private func rows(_ items: [ReceiptListItem]) -> some View {
    ForEach(items) { item in
      NavigationLink(value: PhotoDetailRoute(asset: item.asset, gifticon: nil)) {
        ReceiptRow(categoryModel: self.categoryModel, item: item, calendar: self.model.calendar)
      }
    }
  }

  /// 섹션을 나눈 달력으로 형식화해 머리의 달이 섹션의 달과 같다.
  private func monthTitle(_ section: ReceiptMonthSection) -> Text {
    guard section.month != nil, let date = section.items.first?.asset.creationDate else {
      return Text("날짜 없음")
    }
    return Text(date, format: ReceiptDateText.monthStyle(calendar: self.model.calendar))
  }

  private func storeTitle(_ section: ReceiptStoreSection) -> String {
    switch section.kind {
    case .store: section.storeName ?? "가게 모름"
    case .unknownStore: "가게 모름"
    case .checking: "확인 중"
    }
  }
}

/// 섹션 머리: 제목과 합계 줄. 합계 줄에 쓸 것이 없으면(취소만 있는 섹션, 확인 중 섹션) 제목만 그린다.
private struct ReceiptSectionHeader: View {
  let title: Text
  let totals: ReceiptTotals?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      self.title
      if let totals = self.totals, let text = ReceiptTotalsText.text(totals) {
        Text(text)
          .font(.footnote.monospacedDigit())
      }
    }
    // "US$" 처럼 통화 표시가 대문자로 바뀌지 않게 한다.
    .textCase(nil)
  }
}

/// 확인 중(글자 읽기 대기·추출 대기)이 있는 섹션의 안내. 돌아가는 표시 없이 정적 문구다.
private struct ReceiptCheckingFooter: View {
  var body: some View {
    Text("글자를 읽으면 가게와 금액을 찾습니다. iCloud 에만 있는 사진은 기기에 내려받은 뒤 확인합니다.")
  }
}

/// 섹션 합계 문구(예: "₩182,400 · US$45.20 · 금액 모름 1장 · 확인 중 2장"). 통화 표시는 화면 로캘의 기본 형식이다.
enum ReceiptTotalsText {
  static func text(_ totals: ReceiptTotals) -> String? {
    var parts = totals.currencies.map { total in
      total.amount.formatted(.currency(code: total.currency.rawValue))
    }
    if totals.unknownAmountCount > 0 {
      parts.append("금액 모름 \(totals.unknownAmountCount)장")
    }
    if totals.checkingCount > 0 {
      parts.append("확인 중 \(totals.checkingCount)장")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  static func amount(_ amount: ReceiptAmount) -> String {
    amount.value.formatted(.currency(code: amount.currency.rawValue))
  }
}

/// 영수증 한 줄: 썸네일·가게·금액·날짜. 취소 전표는 금액에 취소선과 "취소" 캡슐을 붙인다.
private struct ReceiptRow: View {
  let categoryModel: CategoryModel
  let item: ReceiptListItem
  let calendar: Calendar

  var body: some View {
    HStack(spacing: 12) {
      CategoryThumbnailCell(model: self.categoryModel, asset: self.item.asset, category: .receipt)
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
        // 썸네일 설명에도 날짜가 있어 줄의 날짜가 두 번 읽히지 않게 한다.
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        switch self.item.status {
        case .checking:
          Text("확인 중")
            .foregroundStyle(.secondary)
        case let .extracted(info):
          Text(info.storeName ?? "가게 모름")
            .foregroundStyle(info.storeName == nil ? .secondary : .primary)
            .lineLimit(1)
          self.amountLine(info)
            .font(.subheadline)
        }
        self.dateText
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private func amountLine(_ info: ReceiptInfo) -> some View {
    if let amount = info.amount {
      HStack(spacing: 6) {
        Text(ReceiptTotalsText.amount(amount))
          .monospacedDigit()
          .strikethrough(info.isCancelled)
          .foregroundStyle(info.isCancelled ? .secondary : .primary)
        if info.isCancelled {
          ReceiptCancelledBadge()
        }
      }
    } else {
      HStack(spacing: 6) {
        Text("금액 모름")
          .foregroundStyle(.secondary)
        if info.isCancelled {
          ReceiptCancelledBadge()
        }
      }
    }
  }

  private var dateText: Text {
    guard let date = self.item.asset.creationDate else { return Text("날짜 없음") }
    return Text(date, format: ReceiptDateText.dayStyle(calendar: self.calendar))
  }
}

/// 취소 전표 표시. 합계에 넣지 않는다는 뜻이다.
private struct ReceiptCancelledBadge: View {
  var body: some View {
    Text("취소")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .foregroundStyle(.secondary)
      .background(SnapColor.neutral, in: .capsule)
      .accessibilityLabel(Text("취소한 결제"))
  }
}
