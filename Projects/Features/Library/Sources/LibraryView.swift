import Core
import SwiftUI

/// Model 은 App 이 소유하고 주입한다. @Observable 이므로 View 는 참조만 들고 있어도 변경을 관찰한다.
/// 카테고리 줄을 누르면 카테고리 화면(`CategoryView`, 기프티콘은 `GifticonListView`, 영수증은 `ReceiptListView`, 여행은 `TripListView`)을,
/// 그 칸·줄을 누르면 사진 상세(`PhotoDetailView`. 여행 줄은 여행 폴더 상세 `TripDetailView` 를 거친다)를 연다.
/// 검색 필드(`.searchable`)를 누르면 카테고리 목록 대신 검색 결과(`SearchResultsView`)를 보이고, 결과의 카테고리·여행·사진 줄이 같은 화면들을 연다.
/// 이동 경로는 NavigationStack 이 갖는 화면 일시 상태이고, 읽기는 각 화면의 `.task` 에서 그 화면 Model 의 이벤트로 한다.
/// 같은 Feature 안 Model 사이의 신호는 모두 이 View 가 넘긴다(docs/ARCHITECTURE.md §1 규칙 6):
/// - 저장소 변경(`LibraryModel.storeRevision`) → 카테고리 화면·기프티콘 목록·영수증 목록·여행 폴더 목록·여행 폴더 상세·사진 상세·검색 결과의 다시 읽기
/// - 사용 여부 쓰기(`CaptureActionsModel.usageRevision`) → 만료 알림 동기화·기프티콘 목록·상세의 다시 읽기
/// - 앱 복귀(scenePhase `.active`)·날짜 변경·시간대 변경 → 날짜를 쓰는 일곱 Model(알림·기프티콘 목록·영수증 목록·사진 상세·여행 폴더 목록·여행 폴더 상세·검색)
public struct LibraryView: View {
  let model: LibraryModel
  let categoryModel: CategoryModel
  let gifticonListModel: GifticonListModel
  let receiptListModel: ReceiptListModel
  let captureActionsModel: CaptureActionsModel
  let tripListModel: TripListModel
  let tripDetailModel: TripDetailModel
  let searchModel: SearchModel

  @Environment(\.scenePhase) private var scenePhase

  public init(
    model: LibraryModel,
    categoryModel: CategoryModel,
    gifticonListModel: GifticonListModel,
    receiptListModel: ReceiptListModel,
    captureActionsModel: CaptureActionsModel,
    tripListModel: TripListModel,
    tripDetailModel: TripDetailModel,
    searchModel: SearchModel
  ) {
    self.model = model
    self.categoryModel = categoryModel
    self.gifticonListModel = gifticonListModel
    self.receiptListModel = receiptListModel
    self.captureActionsModel = captureActionsModel
    self.tripListModel = tripListModel
    self.tripDetailModel = tripDetailModel
    self.searchModel = searchModel
  }

  public var body: some View {
    NavigationStack {
      LibrarySearchContainer(
        searchModel: self.searchModel,
        categoryModel: self.categoryModel,
        isLimited: self.model.isLimited
      ) {
        self.categoryList
      }
      .navigationTitle("SnapSort")
      .safeAreaInset(edge: .top) {
        if self.model.isLimited {
          self.limitedAccessBanner
        }
      }
      .searchable(
        text: Binding(get: { self.searchModel.query }, set: { self.searchModel.queryChanged($0) }),
        prompt: Text("글자·쇼핑몰·지역·장소 검색")
      )
      // 자동 고침이 검색 낱말을 바꾸지 않게 하려는 것이다. 검색 필드에 적용되는지는 실기기에서 확인한다.
      .autocorrectionDisabled()
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
      self.searchModel.libraryStoreChanged()
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
      self.searchModel.dayChanged()
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
    self.searchModel.dayChanged()
  }

  /// 카테고리 줄 목록. 검색 중에는 `SearchResultsView` 가 대신 보인다.
  private var categoryList: some View {
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
  }

  private var emptyDescription: String {
    if self.model.isIndexing {
      "이미지를 분류하는 중입니다."
    } else {
      "분류된 이미지가 없습니다."
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

/// 검색 중이면 `SearchResultsView`, 아니면 카테고리 목록(`content`)을 보인다.
/// `isSearching` 은 `.searchable` 을 붙인 뷰의 안쪽에서만 읽히므로 이 자식 뷰가 읽는다.
/// 검색어가 남아 있으면 `isSearching` 이 상세를 다녀오며 바뀌어도 결과를 계속 보인다.
private struct LibrarySearchContainer<Content: View>: View {
  let searchModel: SearchModel
  let categoryModel: CategoryModel
  let isLimited: Bool
  @ViewBuilder let content: Content

  @Environment(\.isSearching) private var isSearching

  private var showsSearch: Bool {
    self.isSearching || !self.searchModel.query.isEmpty
  }

  var body: some View {
    Group {
      if self.showsSearch {
        SearchResultsView(model: self.searchModel, categoryModel: self.categoryModel, isLimited: self.isLimited)
      } else {
        self.content
      }
    }
    .onChange(of: self.showsSearch) { _, shows in
      if !shows {
        self.searchModel.searchDismissed()
      }
    }
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
