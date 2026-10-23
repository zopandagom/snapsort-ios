import Core
import SwiftUI

/// Model 은 App 이 소유하고 주입한다. @Observable 이므로 View 는 참조만 들고 있어도 변경을 관찰한다.
/// 카테고리 줄을 누르면 카테고리 화면(`CategoryView`, 기프티콘은 `GifticonListView`, 영수증은 `ReceiptListView`, 여행은 `TripListView`)을,
/// 그 칸·줄을 누르면 사진 상세(`PhotoDetailView`. 여행 줄은 여행 폴더 상세 `TripDetailView` 를 거친다)를 연다.
/// 이동 경로는 NavigationStack 이 갖는 화면 일시 상태이고, 읽기는 각 화면의 `.task` 에서 그 화면 Model 의 이벤트로 한다.
/// 같은 Feature 안 Model 사이의 신호는 모두 이 View 가 넘긴다(docs/ARCHITECTURE.md §1 규칙 6):
/// - 저장소 변경(`LibraryModel.storeRevision`) → 카테고리 화면·기프티콘 목록·영수증 목록·여행 폴더 목록·여행 폴더 상세·사진 상세의 다시 읽기
/// - 사용 여부 쓰기(`CaptureActionsModel.usageRevision`) → 만료 알림 동기화·기프티콘 목록·상세의 다시 읽기
/// - 앱 복귀(scenePhase `.active`)·날짜 변경·시간대 변경 → 날짜를 쓰는 여섯 Model(알림·기프티콘 목록·영수증 목록·사진 상세·여행 폴더 목록·여행 폴더 상세)
public struct LibraryView: View {
  let model: LibraryModel
  let categoryModel: CategoryModel
  let gifticonListModel: GifticonListModel
  let receiptListModel: ReceiptListModel
  let captureActionsModel: CaptureActionsModel
  let tripListModel: TripListModel
  let tripDetailModel: TripDetailModel

  @Environment(\.scenePhase) private var scenePhase

  public init(
    model: LibraryModel,
    categoryModel: CategoryModel,
    gifticonListModel: GifticonListModel,
    receiptListModel: ReceiptListModel,
    captureActionsModel: CaptureActionsModel,
    tripListModel: TripListModel,
    tripDetailModel: TripDetailModel
  ) {
    self.model = model
    self.categoryModel = categoryModel
    self.gifticonListModel = gifticonListModel
    self.receiptListModel = receiptListModel
    self.captureActionsModel = captureActionsModel
    self.tripListModel = tripListModel
    self.tripDetailModel = tripDetailModel
  }

  public var body: some View {
    NavigationStack {
      List {
        self.indexingSection
        if self.model.showsExpiryReminderButton {
          self.expiryReminderSection
        }
        if self.model.showsNotificationSettingsButton {
          self.notificationSettingsSection
        }
        // 덮는 overlay 로 두면 위의 진행률·다시 시도를 가리므로 목록 안에 둔다.
        if self.model.categoryCounts.isEmpty {
          Section {
            ContentUnavailableView(
              "이미지 \(self.model.imageCount)장",
              systemImage: "photo.stack",
              description: Text(self.emptyDescription)
            )
          }
        }
        self.categorySection("캡처", group: .information)
        self.categorySection("사진", group: .photo)
        self.categorySection("기타", group: .other)
      }
      .navigationTitle("SnapSort")
      .safeAreaInset(edge: .top) {
        if self.model.isLimited {
          self.limitedAccessBanner
        }
      }
      // 격자 안에 두지 않고 루트 한곳에 둔다.
      .navigationDestination(for: ImageCategory.self) { category in
        switch category {
        case .gifticon:
          GifticonListView(model: self.gifticonListModel, categoryModel: self.categoryModel)
        case .receipt:
          ReceiptListView(model: self.receiptListModel, categoryModel: self.categoryModel)
        case .travel:
          TripListView(model: self.tripListModel, categoryModel: self.categoryModel)
        default:
          CategoryView(model: self.categoryModel, category: category)
        }
      }
      .navigationDestination(for: TripFolderRoute.self) { route in
        TripDetailView(model: self.tripDetailModel, categoryModel: self.categoryModel, route: route)
      }
      .navigationDestination(for: PhotoDetailRoute.self) { route in
        PhotoDetailView(model: self.categoryModel, captureModel: self.captureActionsModel, route: route)
      }
    }
    // 모두 NavigationStack 에 붙여 둔다. 화면을 push 해도 이 View 는 계층에 남아 인덱싱이 이어지고 신호를 넘긴다.
    .task { await self.model.onAppear() }
    .onChange(of: self.model.storeRevision) {
      self.categoryModel.libraryStoreChanged()
      self.gifticonListModel.libraryStoreChanged()
      self.receiptListModel.libraryStoreChanged()
      self.captureActionsModel.libraryStoreChanged()
      self.tripListModel.libraryStoreChanged()
      self.tripDetailModel.libraryStoreChanged()
    }
    // 상세를 닫은 뒤 끝난 쓰기도 오른다. 같은 사진을 닫았다 바로 다시 열어 경로의 옛 값을 보이는 상세도 다시 읽어 맞춘다.
    .onChange(of: self.captureActionsModel.usageRevision) {
      self.model.gifticonUsageChanged()
      self.gifticonListModel.libraryStoreChanged()
      self.captureActionsModel.libraryStoreChanged()
    }
    // 시작 직후의 첫 값은 부르지 않는다(화면 진입 동기화가 맡는다). 백그라운드(잠금 포함) 동안의 날짜 변경도 여기서 덮는다.
    .onChange(of: self.scenePhase) { _, phase in
      guard phase == .active else { return }
      self.model.sceneBecameActive()
      self.gifticonListModel.dayChanged()
      self.receiptListModel.dayChanged()
      self.captureActionsModel.dayChanged()
      self.tripListModel.dayChanged()
      self.tripDetailModel.dayChanged()
    }
    // 아래 두 알림 모두 백그라운드 큐에서 post 해도 `.onReceive` 의 action 은 메인에서 돈다(iOS 26.5 시뮬레이터 실험으로 확인).
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      self.dayChanged()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      self.dayChanged()
    }
  }

  private func dayChanged() {
    self.model.dayChanged()
    self.gifticonListModel.dayChanged()
    self.receiptListModel.dayChanged()
    self.captureActionsModel.dayChanged()
    self.tripListModel.dayChanged()
    self.tripDetailModel.dayChanged()
  }

  private var emptyDescription: String {
    if self.model.isIndexing {
      "이미지를 분류하는 중입니다."
    } else {
      "분류된 이미지가 없습니다."
    }
  }

  /// 분석 중일 때와 멈췄을 때만 보인다. 정상으로 다 분석하면 숨기되, 미룬 이미지가 있으면 그 수는 남겨 안내한다.
  /// `isFinished` 는 미룬 수까지 더해 판단하므로, 숨기기만 하면 iCloud 에만 있는 사진처럼 분류되지 않은 이유가 사라진다.
  /// 분석 중이면 진행률의 `phase` 로 분류 중(1단계) 막대와 글자 읽는 중(2단계) 막대를 나눠 보인다.
  /// 첫 진행률을 받기 전에 멈출 수도 있으므로(저장소 실패 등), 멈춤 안내는 진행률이 없어도 띄운다.
  /// 첫 진행률은 보관함과 저장소 비교를 마친 뒤에 오므로, 그 전에는 준비 중으로 보여 준다.
  @ViewBuilder
  private var indexingSection: some View {
    if self.model.isIndexingStopped {
      Section {
        HStack {
          Label(self.stoppedText, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
          Spacer()
          Button("다시 시도") {
            self.model.retryIndexingTapped()
          }
          .buttonStyle(.bordered)
          .font(.subheadline)
        }
      }
    } else if let progress = self.model.indexingProgress, progress.phase == .classifying {
      let doneCount = progress.indexedCount + progress.skippedCount
      Section {
        ProgressView(value: Double(doneCount), total: Double(max(progress.totalCount, 1))) {
          Text("이미지 분류 중")
        } currentValueLabel: {
          Text("\(doneCount)/\(progress.totalCount)장")
        }
      } footer: {
        if progress.skippedCount > 0 {
          Text("읽지 못한 \(progress.skippedCount)장은 다음에 다시 시도합니다.")
        }
      }
    } else if let progress = self.model.indexingProgress, progress.phase == .recognizingText {
      // 분모는 이번 실행에서 남은 일이다. 새 사진이 대기에 더해지면 늘어난다.
      let doneCount = progress.recognizedTextCount + progress.skippedTextCount
      let totalCount = doneCount + progress.pendingTextCount
      Section {
        ProgressView(value: Double(doneCount), total: Double(max(totalCount, 1))) {
          Text("글자 읽는 중")
        } currentValueLabel: {
          Text("\(doneCount)/\(totalCount)장")
        }
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text("사진 분류는 끝났습니다. 기프티콘·영수증 같은 캡처는 글자를 읽으며 채웁니다.")
          if progress.skippedTextCount > 0 {
            Text("글자를 읽지 못한 \(progress.skippedTextCount)장은 다음에 다시 시도합니다.")
          }
          if progress.skippedCount > 0 {
            Text("읽지 못한 \(progress.skippedCount)장은 다음에 다시 시도합니다.")
          }
        }
      }
    } else if self.model.isIndexing {
      Section {
        HStack(spacing: 12) {
          ProgressView()
          Text("이미지 분류 준비 중")
        }
      }
    } else if let progress = self.model.indexingProgress, progress.skippedCount + progress.skippedTextCount > 0 {
      // 1단계·2단계 미룸은 이용자에게 같은 이유(iCloud 에만 있거나 읽을 수 없음)라 합쳐 센다.
      Section {
        Label(
          "읽지 못한 \(progress.skippedCount + progress.skippedTextCount)장은 다음에 다시 시도합니다",
          systemImage: "icloud.slash"
        )
        .font(.subheadline)
      } footer: {
        Text("iCloud 에만 있거나 읽을 수 없는 사진입니다.")
      }
    }
  }

  /// 멈춘 단계로 고른다. 다 분석한 뒤 증분 반영 중에 멈추면 마지막 진행률이 n/n 이므로, 개수 대신 새 사진을 분류하지 못했다고 안내한다.
  private var stoppedText: String {
    guard let progress = self.model.indexingProgress else { return "분류를 마치지 못했습니다" }
    switch progress.phase {
    case .classifying:
      return "분류를 마치지 못했습니다 (\(progress.indexedCount + progress.skippedCount)/\(progress.totalCount))"
    case .recognizingText:
      return "글자 읽기를 마치지 못했습니다 (남은 \(progress.pendingTextCount)장)"
    case .finished:
      return "새 사진을 분류하지 못했습니다"
    }
  }

  /// 이미지가 있는 카테고리만 보여 주고, 하나도 없으면 섹션째 숨긴다. 기프티콘 줄은 기프티콘 목록, 영수증 줄은 영수증 목록, 여행 줄은 여행 폴더 목록을 연다.
  @ViewBuilder
  private func categorySection(_ title: String, group: ImageCategoryGroup) -> some View {
    let rows = ImageCategory.allCases.compactMap { category in
      self.model.categoryCounts[category].map { (category: category, count: $0) }
    }
    .filter { $0.category.group == group }
    if !rows.isEmpty {
      Section {
        ForEach(rows, id: \.category) { row in
          NavigationLink(value: row.category) {
            self.categoryRow(row.category, count: row.count)
          }
        }
      } header: {
        Text(title)
      } footer: {
        // 여행은 고른 사진만으로 판정하므로 제한 접근이면 실제 여행과 다를 수 있다 (docs/ARCHITECTURE.md §4 여행 판정).
        if group == .photo, self.model.isLimited, self.model.categoryCounts[.travel] != nil {
          Text("선택한 사진만으로 여행을 찾아 정확하지 않을 수 있습니다.")
        }
        // 정보형 카테고리는 2단계에서 글자를 읽으며 더해진다 (docs/ARCHITECTURE.md §4 인덱싱).
        if group == .information, self.model.isIndexing, self.model.indexingProgress?.phase == .recognizingText {
          Text("글자를 읽는 중이라 개수가 늘어날 수 있습니다.")
        }
      }
    }
  }

  private func categoryRow(_ category: ImageCategory, count: Int) -> some View {
    LabeledContent {
      Text(category.countText(count))
    } label: {
      Label(category.title, systemImage: category.systemImage)
    }
  }

  private var limitedAccessBanner: some View {
    HStack(spacing: 12) {
      Label("선택한 사진만 분류합니다", systemImage: "photo.badge.checkmark")
        .font(.subheadline)
      Spacer()
      Button("사진 더 선택") {
        Task { await self.model.selectMorePhotosTapped() }
      }
      .buttonStyle(.bordered)
      .font(.subheadline)
    }
    .padding()
    .background(.thinMaterial, in: .rect(cornerRadius: 12))
    .padding(.horizontal)
  }
}

// MARK: - 알림 안내

extension LibraryView {
  /// 권한을 정하지 않았고 지금 예약할 만료 알림이 있을 때만 보인다 (docs/ARCHITECTURE.md §4 만료 알림).
  private var expiryReminderSection: some View {
    Section {
      HStack {
        Label("기프티콘 만료일이 다가오면 알려 드려요", systemImage: "bell")
          .font(.subheadline)
        Spacer()
        Button("만료 알림 받기") {
          Task { await self.model.notificationsTapped() }
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
      }
    }
  }

  /// 알림을 거부했고 지금 예약할 알림이 있을 때만 보인다 (docs/ARCHITECTURE.md §4 만료 알림).
  private var notificationSettingsSection: some View {
    Section {
      HStack {
        Label("만료 알림이 꺼져 있어요", systemImage: "bell.slash")
          .font(.subheadline)
        Spacer()
        Button("설정에서 알림 켜기") {
          Task { await self.model.notificationSettingsTapped() }
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
      }
    }
  }
}

/// 화면에 보이는 이름과 아이콘. Core 는 SwiftUI·문구를 갖지 않으므로 화면 쪽에 둔다.
extension ImageCategory {
  var title: String {
    switch self {
    case .gifticon: "기프티콘"
    case .receipt: "영수증"
    case .chat: "대화 캡처"
    case .shopping: "쇼핑"
    case .map: "지도"
    case .document: "문서·메모"
    case .travel: "여행"
    case .food: "음식"
    case .people: "인물"
    case .pet: "반려동물"
    case .landscape: "풍경"
    case .other: "기타"
    }
  }

  var systemImage: String {
    switch self {
    case .gifticon: "gift"
    case .receipt: "receipt"
    case .chat: "bubble.left.and.bubble.right"
    case .shopping: "bag"
    case .map: "map"
    case .document: "doc.text"
    case .travel: "airplane"
    case .food: "fork.knife"
    case .people: "person.2"
    case .pet: "pawprint"
    case .landscape: "mountain.2"
    case .other: "square.grid.2x2"
    }
  }

  /// 여행은 이미지 수가 아니라 여행 수를 센다 (`LibraryModel.categoryCounts`).
  func countText(_ count: Int) -> String {
    self == .travel ? "\(count)번" : "\(count)장"
  }
}
