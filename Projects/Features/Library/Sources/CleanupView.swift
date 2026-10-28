import Core
import DesignSystem
import SwiftUI

/// 정리 화면: 만료된 기프티콘과 사용한 기프티콘, 비슷한 사진 묶음을 후보로 보이고, 고른 것을 지운다 (docs/ARCHITECTURE.md §4 정리 도우미).
/// 비슷한 사진은 묶음마다 목록 섹션 하나로 그리고, 첫 묶음 머리에 섹션 제목과 "모두 선택"을, 마지막 묶음 바닥에 섹션 바닥글을 둔다.
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
      .snapScreenBackground()
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
      SnapList {
        if self.model.isLimited {
          CleanupLimitedSection {
            Task { await self.model.selectMorePhotosTapped() }
          }
        }
        Section {
          StatusMessageView("정리 후보를 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
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
    SnapList {
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
          StatusMessageView("정리할 항목이 없습니다", systemImage: "checkmark.circle")
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
        if sections.uncomparedPhotoCount > 0 {
          CleanupFootnote(
            "아직 비교하지 않은 사진 \(sections.uncomparedPhotoCount)장은 비교를 마치면 비슷한 사진 묶음에 들 수 있습니다. "
              + "기기에 작은 버전만 있는 iCloud 사진은 비교하지 못할 수 있습니다."
          )
        }
        CleanupFootnote(CleanupText.sizeEstimateNote)
      }
    }
  }

  @ViewBuilder
  private func sectionView(_ section: CleanupSection) -> some View {
    switch section.kind {
    case .expiredGifticons, .usedGifticons:
      Section {
        ForEach(section.candidates) { candidate in
          self.row(candidate)
        }
      } header: {
        self.sectionHeader(section)
      } footer: {
        if section.kind == .expiredGifticons,
           section.candidates.contains(where: { $0.gifticon?.estimatedFields.contains(.expiryDate) == true })
        {
          Text("추정한 만료일은 기본으로 고르지 않았습니다.")
        }
      }
    case .similarPhotos:
      ForEach(section.groups) { group in
        Section {
          ForEach(group.candidates) { candidate in
            self.row(candidate)
          }
        } header: {
          VStack(alignment: .leading, spacing: 8) {
            if group.id == section.groups.first?.id {
              self.sectionHeader(section)
            }
            Text(self.groupTitle(group))
              .textCase(nil)
          }
        } footer: {
          if group.id == section.groups.last?.id {
            Text("묶음마다 가장 큰 사진 한 장은 남김으로 두고 고르지 않았습니다.")
          }
        }
      }
    }
  }

  /// 섹션 제목과 "모두 선택/모두 해제". 비슷한 사진의 "모두 선택"은 남길 장을 고르지 않는다(`bulkSelectableIDs`).
  private func sectionHeader(_ section: CleanupSection) -> some View {
    let isAllSelected = section.bulkSelectableIDs.isSubset(of: self.model.selectedIDs)
    return HStack {
      Text(section.kind.title)
      Spacer()
      Button(isAllSelected ? "모두 해제" : "모두 선택") {
        self.model.sectionSelectionToggled(section.kind)
      }
      .buttonStyle(.borderless)
      // 루트 `snapTheme()` 의 본문 글자색이 버튼 tint 를 덮지 않게 강조색을 직접 준다.
      .foregroundStyle(.tint)
      .textCase(nil)
    }
  }

  /// 묶음 머리말: 장수와 첫 장 촬영 시각.
  private func groupTitle(_ group: CleanupCandidateGroup) -> String {
    let count = "\(group.candidates.count)장"
    guard let date = group.candidates.first?.asset.creationDate else { return count }
    return "\(count) · \(date.formatted(CleanupText.photoTimeStyle(calendar: self.model.calendar)))"
  }

  private func row(_ candidate: CleanupCandidate) -> some View {
    let isSelected = self.model.selectedIDs.contains(candidate.id)
    return HStack(spacing: 12) {
      Button {
        self.model.candidateToggled(id: candidate.id)
      } label: {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? AnyShapeStyle(SnapColor.accent) : AnyShapeStyle(.secondary))
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(isSelected ? "선택 해제" : "선택")
      NavigationLink(value: PhotoDetailRoute(asset: candidate.asset, gifticon: candidate.gifticon)) {
        if let item = candidate.gifticon {
          CleanupCandidateRow(
            categoryModel: self.categoryModel,
            item: item,
            today: self.model.today,
            calendar: self.model.calendar
          )
        } else {
          CleanupSimilarPhotoRow(
            categoryModel: self.categoryModel,
            candidate: candidate,
            calendar: self.model.calendar
          )
        }
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
      // 알약 버튼의 삭제와 같은 경고색 (`SnapButtonStyle`). 루트 `snapTheme()` 의 본문 글자색이 tint 를 덮어 글자색을 직접 주고,
      // 그래서 시스템이 흐리게 하지 않는 비활성 상태는 보조 글자색으로 그린다.
      .foregroundStyle(
        self.model.selectionCount == 0 ? AnyShapeStyle(SnapColor.inkSecondary) : AnyShapeStyle(SnapColor.danger)
      )
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

/// 비슷한 사진 한 줄의 사진 쪽: 썸네일·촬영 시각(초까지)·남길 장이면 "남김".
private struct CleanupSimilarPhotoRow: View {
  let categoryModel: CategoryModel
  let candidate: CleanupCandidate
  let calendar: Calendar

  var body: some View {
    HStack(spacing: 12) {
      CategoryThumbnailCell(model: self.categoryModel, asset: self.candidate.asset, scope: .cleanup)
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
      if let date = self.candidate.asset.creationDate {
        Text(date, format: CleanupText.photoTimeStyle(calendar: self.calendar))
          .font(.subheadline)
      }
      Spacer()
      if self.candidate.isKept {
        Text("남김")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(SnapColor.neutral, in: .capsule)
          .foregroundStyle(.secondary)
      }
    }
  }
}
