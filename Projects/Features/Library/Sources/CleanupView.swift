import Core
import DesignSystem
import SwiftUI

/// 정리 화면: 만료된 기프티콘과 사용한 기프티콘을 후보로 보이고, 고른 것을 지운다 (docs/ARCHITECTURE.md §4 정리 도우미).
/// 맨 위에서 캡처 인박스(`CaptureInboxView`)로 간다. 후보 줄은 체크 원(선택)과 나머지(사진 상세로 가는 링크)로 나뉜다:
/// 사진을 보고 고르게 하려는 것이라 체크 원이 아닌 곳을 누르면 선택이 바뀌지 않는다.
/// 큰 제목이 흐려지지 않게 안내는 목록 첫 섹션으로 두고, 선택 수·확보 용량을 담은 삭제 버튼은 아래 도구 막대에 둔다
/// (iOS 26 도구 막대는 글자만 있는 항목을 작은 원으로 줄여, 요약을 따로 두면 잘린다).
/// 썸네일은 `CategoryModel` 의 칸을 빌린다(`thumbnailScreenAppeared(scope: .cleanup)`).
/// 화면을 새로 열 때마다 새 방문 번호를 만들어, 지난 방문의 선택·안내가 보이지 않게 한다.
public struct CleanupView: View {
  let model: CleanupModel
  let categoryModel: CategoryModel

  @State private var visit = UUID()

  public init(model: CleanupModel, categoryModel: CategoryModel) {
    self.model = model
    self.categoryModel = categoryModel
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("정리 도우미")
      .toolbar {
        if self.isLoaded {
          ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            self.deleteButton
          }
        }
      }
      .cleanupAlert(self.model.alert) { self.model.alertDismissed() }
      .task { await self.model.onAppear(visit: self.visit) }
      .task { await self.categoryModel.thumbnailScreenAppeared(scope: .cleanup) }
  }

  /// 이전 방문의 내용이 남아 있으면 쓰지 않고 불러오는 중으로 그린다.
  private var content: CleanupContent {
    self.model.visit == self.visit ? self.model.content : .loading
  }

  private var isLoaded: Bool {
    if case .loaded = self.content {
      true
    } else {
      false
    }
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.content {
    case .loading:
      ProgressView()
    case .failed:
      // 실패해도 제한 접근 안내와 "사진 더 선택"이 첫 섹션에 남게 목록 안에 그린다.
      List {
        if self.model.isLimited {
          CleanupLimitedSection {
            Task { await self.model.selectMorePhotosTapped() }
          }
        }
        Section {
          StatusMessageView("기프티콘을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
            self.model.retryButtonTapped()
          }
          .listRowBackground(Color.clear)
        }
      }
    case let .loaded(sections):
      if self.categoryModel.thumbnailScope != .cleanup {
        // 지난 화면의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 줄을 그린다(`GifticonListView` 와 같은 이유).
        ProgressView()
      } else {
        self.list(sections)
      }
    }
  }

  private func list(_ sections: CleanupSections) -> some View {
    List {
      if self.model.isLimited {
        CleanupLimitedSection {
          Task { await self.model.selectMorePhotosTapped() }
        }
      }
      if let notice = self.model.notice {
        CleanupNoticeSection(notice: notice) { self.model.noticeDismissed() }
      }
      Section {
        NavigationLink(value: CleanupRoute.captureInbox) {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("캡처 인박스")
              Text("최근 30일 스크린샷을 한 장씩 정리")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "tray.full")
          }
        }
      }
      if sections.isEmpty {
        Section {
          StatusMessageView("정리할 기프티콘이 없습니다", systemImage: "checkmark.circle")
            .listRowBackground(Color.clear)
        }
      }
      ForEach(sections.sections) { section in
        self.sectionView(section)
      }
      Section {
        if sections.checkingGifticonCount > 0 {
          CleanupFootnote("확인 중인 기프티콘 \(sections.checkingGifticonCount)장은 만료일을 찾은 뒤 후보가 됩니다.")
        }
        CleanupFootnote(CleanupText.sizeEstimateNote)
      }
    }
  }

  private func sectionView(_ section: CleanupSection) -> some View {
    let isAllSelected = section.candidates.allSatisfy { self.model.selectedIDs.contains($0.id) }
    return Section {
      ForEach(section.candidates) { candidate in
        self.row(candidate)
      }
    } header: {
      HStack {
        Text(section.kind.title)
        Spacer()
        Button(isAllSelected ? "모두 해제" : "모두 선택") {
          self.model.sectionSelectionToggled(section.kind)
        }
        .buttonStyle(.borderless)
        .textCase(nil)
      }
    } footer: {
      if section.kind == .expiredGifticons,
         section.candidates.contains(where: { $0.item.estimatedFields.contains(.expiryDate) })
      {
        Text("추정한 만료일은 기본으로 고르지 않았습니다.")
      }
    }
  }

  private func row(_ candidate: CleanupCandidate) -> some View {
    let isSelected = self.model.selectedIDs.contains(candidate.id)
    return HStack(spacing: 12) {
      Button {
        self.model.candidateToggled(id: candidate.id)
      } label: {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(isSelected ? "선택 해제" : "선택")
      NavigationLink(value: PhotoDetailRoute(asset: candidate.asset, gifticon: candidate.item)) {
        CleanupCandidateRow(
          categoryModel: self.categoryModel,
          item: candidate.item,
          today: self.model.today,
          calendar: self.model.calendar
        )
      }
    }
  }

  @ViewBuilder
  private var deleteButton: some View {
    if self.model.isDeleting {
      ProgressView()
    } else {
      Button(
        "\(self.model.selectionCount)장 삭제 · 약 \(CleanupText.bytes(self.model.selectionBytes)) 확보",
        role: .destructive
      ) {
        Task { await self.model.deleteButtonTapped() }
      }
      .disabled(self.model.selectionCount == 0)
    }
  }
}

/// 후보 한 줄의 사진 쪽: 썸네일·교환처·만료일·D-n. 모델이 채운 값에는 "추정"을 붙인다.
private struct CleanupCandidateRow: View {
  let categoryModel: CategoryModel
  let item: GifticonListItem
  let today: LocalDate
  let calendar: Calendar

  var body: some View {
    HStack(spacing: 12) {
      CategoryThumbnailCell(model: self.categoryModel, asset: self.item.asset, scope: .cleanup)
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
