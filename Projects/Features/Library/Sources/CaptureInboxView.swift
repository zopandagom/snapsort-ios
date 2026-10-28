import Core
import DesignSystem
import SwiftUI

/// 캡처 인박스: 최근 30일의 보관하지 않은 스크린샷을 한 장씩 크게 보며 "보관"하거나 "삭제 표시"하고,
/// 표시한 것을 모아 한 번에 지운다 (docs/ARCHITECTURE.md §4 정리 도우미). 보관은 바로 저장되고, 삭제 표시는 화면을 나가면 사라진다.
/// 이 화면은 다른 화면을 push 하지 않는다. 큰 이미지는 사진 상세와 같은 읽기(`CategoryModel.detailAppeared`)를 쓰고,
/// 표시한 사진의 썸네일은 정리 화면과 같은 칸(`.cleanup`)을 쓴다.
/// 화면을 새로 열 때마다 새 방문 번호를 만들어, 지난 방문의 표시·안내가 보이지 않게 한다.
public struct CaptureInboxView: View {
  let model: CaptureInboxModel
  let categoryModel: CategoryModel

  @State private var visit = UUID()

  public init(model: CaptureInboxModel, categoryModel: CategoryModel) {
    self.model = model
    self.categoryModel = categoryModel
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("캡처 인박스")
      .snapScreenBackground()
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if self.isLoaded {
          ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            self.deleteButton
          }
        }
      }
      .cleanupAlert(self.model.alert) { self.model.alertDismissed() }
      // 지금 장의 큰 이미지는 목록 행이 아니라 화면에서 읽는다. 목록은 상세 상태가 바뀔 때 행을 다시 만들어
      // 행의 `.task` 가 끝없이 취소·재시작된다(시뮬레이터 실측). 지금 장이 바뀌면 지난 읽기를 취소하고 새로 읽는다.
      .task(id: self.currentID) {
        guard let id = self.currentID else { return }
        await self.categoryModel.detailAppeared(id: id)
      }
      .task { await self.model.onAppear(visit: self.visit) }
      .task { await self.categoryModel.thumbnailScreenAppeared(scope: .cleanup) }
  }

  /// 이전 방문의 내용이 남아 있으면 쓰지 않고 불러오는 중으로 그린다.
  private var content: CaptureInboxContent {
    self.model.visit == self.visit ? self.model.content : .loading
  }

  /// 이 방문의 지금 장. 썸네일 칸을 넘겨받기 전이면 그리지 않으므로 읽지 않는다.
  private var currentID: ImageAsset.ID? {
    guard self.isLoaded, self.categoryModel.thumbnailScope == .cleanup else { return nil }
    return self.model.current?.id
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
      // 실패해도 제한 접근 안내와 "사진 더 선택"이 첫 섹션에 남게 목록 안에 그린다(정리 화면과 같다).
      SnapList {
        if self.model.isLimited {
          CleanupLimitedSection {
            Task { await self.model.selectMorePhotosTapped() }
          }
        }
        Section {
          StatusMessageView("스크린샷을 불러오지 못했습니다", systemImage: "exclamationmark.triangle") {
            self.model.retryButtonTapped()
          }
          .listRowBackground(Color.clear)
        }
      }
    case let .loaded(assets):
      if self.categoryModel.thumbnailScope != .cleanup {
        // 지난 화면의 썸네일 칸이 이 화면 칸을 막지 않게, 썸네일 칸을 넘겨받은 뒤에 그린다.
        ProgressView()
      } else {
        self.list(assets)
      }
    }
  }

  /// 대상이 없을 때도 이 목록 안에 그려, 제한 접근 안내와 "사진 더 선택"이 늘 첫 섹션에 남게 한다(정리 화면과 같다).
  private func list(_ assets: [ImageAsset]) -> some View {
    SnapList {
      if self.model.isLimited {
        CleanupLimitedSection {
          Task { await self.model.selectMorePhotosTapped() }
        }
      }
      if let notice = self.model.notice {
        CleanupNoticeSection(notice: notice) { self.model.noticeDismissed() }
      }
      if assets.isEmpty {
        Section {
          StatusMessageView("최근 30일 동안 정리할 스크린샷이 없습니다", systemImage: "checkmark.circle")
            .listRowBackground(Color.clear)
        }
      } else {
        if let current = self.model.current {
          self.currentSection(current)
        } else {
          Section {
            Text("최근 30일 스크린샷을 모두 확인했습니다")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 24)
          }
        }
        if !self.model.markedIDs.isEmpty {
          self.markedSection(assets)
        }
        Section {
          CleanupFootnote("화면을 나가면 삭제 표시는 사라집니다.")
          CleanupFootnote(CleanupText.sizeEstimateNote)
        }
      }
    }
  }

  private func currentSection(_ current: ImageAsset) -> some View {
    Section {
      CaptureInboxPhoto(model: self.categoryModel, asset: current)
        .listRowInsets(EdgeInsets())
      HStack {
        self.dateText(current)
        Spacer()
        if let position = self.model.position {
          Text("\(position.index) / \(position.total)")
            .monospacedDigit()
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      HStack(spacing: 12) {
        Button {
          Task { await self.model.keepTapped() }
        } label: {
          Label("보관", systemImage: "tray.and.arrow.down")
            .frame(maxWidth: .infinity)
        }
        .disabled(self.model.keepingID != nil || self.model.isDeleting)
        Button(role: .destructive) {
          self.model.markForDeletionTapped()
        } label: {
          Label("삭제 표시", systemImage: "trash")
            .frame(maxWidth: .infinity)
        }
        .disabled(self.model.keepingID != nil)
      }
      .buttonStyle(.snapSecondary)
    }
  }

  private func markedSection(_ assets: [ImageAsset]) -> some View {
    let marked = self.model.markedIDs.compactMap { id in assets.first { $0.id == id } }
    return Section {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 8) {
          ForEach(marked) { asset in
            Button {
              self.model.unmarkTapped(id: asset.id)
            } label: {
              CategoryThumbnailCell(model: self.categoryModel, asset: asset, scope: .cleanup)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.borderless)
            .accessibilityHint("눌러서 표시 해제")
          }
        }
      }
      .scrollIndicators(.hidden)
    } header: {
      Text("삭제 표시한 사진 \(marked.count)장")
    } footer: {
      Text("눌러서 표시 해제")
    }
  }

  @ViewBuilder
  private func dateText(_ asset: ImageAsset) -> some View {
    if let date = asset.creationDate {
      Text(date, format: .dateTime.year().month().day().hour().minute())
    } else {
      Text("날짜 없음")
    }
  }

  @ViewBuilder
  private var deleteButton: some View {
    if self.model.isDeleting {
      ProgressView()
    } else {
      Button(
        "\(self.model.markedIDs.count)장 삭제 · 약 \(CleanupText.bytes(self.model.markedBytes)) 확보",
        role: .destructive
      ) {
        Task { await self.model.deleteButtonTapped() }
      }
      // 정리 화면 삭제 버튼과 같은 경고색·비활성 색 (`CleanupView.deleteButton`).
      .foregroundStyle(
        self.model.markedIDs.isEmpty ? AnyShapeStyle(SnapColor.inkSecondary) : AnyShapeStyle(SnapColor.danger)
      )
      .disabled(self.model.markedIDs.isEmpty)
    }
  }
}

/// 지금 장의 큰 이미지. 읽기는 화면(`CaptureInboxView`)이 지금 장 기준으로 하고, 여기서는 상태만 그린다.
/// 볼 수 없을 때와 작은 대체 버전일 때는 사진 상세와 같은 문구를 보인다.
private struct CaptureInboxPhoto: View {
  let model: CategoryModel
  let asset: ImageAsset

  var body: some View {
    self.photo
      .frame(maxWidth: .infinity)
      .frame(height: 420)
  }

  /// 다른 사진의 상세 상태가 남아 있으면 쓰지 않고 불러오는 중으로 그린다.
  private var state: ImageLoadState {
    guard let detail = self.model.detail, detail.id == self.asset.id else { return .loading }
    return detail.state
  }

  @ViewBuilder
  private var photo: some View {
    switch self.state {
    case .loading:
      ProgressView()
    case let .loaded(image):
      VStack(spacing: 8) {
        Image(decorative: image.cgImage, orientation: image.orientation)
          .resizable()
          .scaledToFit()
        if image.isLocalFallback {
          Label("iCloud 원본 대신 기기에 있는 작은 버전입니다", systemImage: "icloud")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("iCloud 원본 대신 기기에 있는 작은 버전입니다"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    case .unavailable(.inCloudOnly):
      StatusMessageView(
        "iCloud 에만 있는 사진입니다",
        systemImage: "icloud.slash",
        description: "사진 앱에서 내려받으면 볼 수 있습니다."
      )
    case .unavailable(.notFound):
      StatusMessageView("보관함에 없는 사진입니다", systemImage: "photo.badge.exclamationmark")
    case .unavailable(.failed):
      StatusMessageView("사진을 불러오지 못했습니다", systemImage: "exclamationmark.triangle")
    }
  }
}
