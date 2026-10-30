import Core
import DesignSystem
import SwiftUI

/// Model 은 App 이 소유하고 주입한다. @Observable 이므로 View 는 참조만 들고 있어도 변경을 관찰한다.
/// 카테고리 카드를 누르면 카테고리 화면(`CategoryView`, 기프티콘은 `GifticonListView`, 영수증은 `ReceiptListView`, 여행은 `TripListView`)을,
/// 그 칸·줄을 누르면 사진 상세(`PhotoDetailView`. 여행 폴더 목록의 줄은 여행 폴더 상세 `TripDetailView` 를 거친다)를 연다.
/// 검색 필드(`.searchable`)를 누르면 카테고리 카드 대신 검색 결과(`SearchResultsView`)를 보이고, 결과의 카테고리·여행·사진 줄이 같은 화면들을 연다.
/// 카테고리 위 "정리 도우미" 카드는 정리 화면(`CleanupView`)을, 그 안의 줄은 최근 스크린샷 화면(`CaptureInboxView`)을 연다.
/// 카드의 대표 썸네일은 `LibraryCoverModel` 이 갖는다(docs/ARCHITECTURE.md §4 카테고리 화면).
/// 이동 경로는 NavigationStack 이 갖는 화면 일시 상태이고, 읽기는 각 화면의 `.task` 에서 그 화면 Model 의 이벤트로 한다.
/// 같은 Feature 안 Model 사이의 신호는 모두 이 View 가 넘긴다(docs/ARCHITECTURE.md §1 규칙 6):
/// - 저장소 변경(`LibraryModel.storeRevision`) → 카테고리 화면·기프티콘 목록·영수증 목록·여행 폴더 목록·여행 폴더 상세·사진 상세·검색 결과·정리 화면·최근 스크린샷 화면의 다시
/// 읽기
/// - 장소 캐시 쓰기(`LibraryModel.placeRevision`, 장소 이름 미리 받기) → 여행 폴더 목록·여행 폴더 상세·검색 결과의 다시 읽기
/// - 대표 사진 변경(`LibraryModel.coverIDs`) → 카드 대표 썸네일 읽기·놓기(`LibraryCoverModel.coversChanged`)
/// - 사용 여부 쓰기(`CaptureActionsModel.usageRevision`) → 만료 알림 동기화·기프티콘 목록·정리 화면·상세의 다시 읽기
/// - 앱 복귀(scenePhase `.active`)·날짜 변경·시간대 변경(날짜·시간대는 앱이 앞에 있을 때만) → 날짜를 쓰는 아홉 Model(알림·기프티콘 목록·
/// 영수증 목록·사진 상세·여행 폴더 목록·여행 폴더 상세·검색·정리 화면·최근 스크린샷 화면)
/// - 기기 로캘 변경 → 장소 이름 미리 받기(`LibraryModel.localeChanged`)
/// - 앱이 앞으로 옴·뒤로 감(scenePhase `.active`·`.background`. `.background` 는 처음 값 포함, 앞에서 켤 때 처음 값은 `.inactive`)
/// → 분류 멈춤·재개와 BG 작업(`LibraryModel.sceneBecameActive`·
/// `sceneEnteredBackground`). 보관함 화면 진입(`LibraryModel.onAppear`)은 첫 `.active` 까지 기다린다
public struct LibraryView: View {
  let model: LibraryModel
  let coverModel: LibraryCoverModel
  let categoryModel: CategoryModel
  let gifticonListModel: GifticonListModel
  let receiptListModel: ReceiptListModel
  let captureActionsModel: CaptureActionsModel
  let tripListModel: TripListModel
  let tripDetailModel: TripDetailModel
  let searchModel: SearchModel
  let cleanupModel: CleanupModel
  let captureInboxModel: CaptureInboxModel

  @Environment(\.scenePhase) private var scenePhase
  /// 카드 격자의 열 수·이름 줄 수를 정한다(`LibraryView+Grid.swift`).
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  public init(
    model: LibraryModel,
    coverModel: LibraryCoverModel,
    categoryModel: CategoryModel,
    gifticonListModel: GifticonListModel,
    receiptListModel: ReceiptListModel,
    captureActionsModel: CaptureActionsModel,
    tripListModel: TripListModel,
    tripDetailModel: TripDetailModel,
    searchModel: SearchModel,
    cleanupModel: CleanupModel,
    captureInboxModel: CaptureInboxModel
  ) {
    self.model = model
    self.coverModel = coverModel
    self.categoryModel = categoryModel
    self.gifticonListModel = gifticonListModel
    self.receiptListModel = receiptListModel
    self.captureActionsModel = captureActionsModel
    self.tripListModel = tripListModel
    self.tripDetailModel = tripDetailModel
    self.searchModel = searchModel
    self.cleanupModel = cleanupModel
    self.captureInboxModel = captureInboxModel
  }

  public var body: some View {
    NavigationStack {
      LibrarySearchContainer(
        searchModel: self.searchModel,
        categoryModel: self.categoryModel,
        isLimited: self.model.isLimited
      ) {
        self.homeGrid
      }
      .navigationTitle("간직함")
      .snapScreenBackground()
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
      .navigationDestination(for: CleanupRoute.self) { route in
        switch route {
        case .cleanup:
          CleanupView(model: self.cleanupModel, categoryModel: self.categoryModel)
        case .captureInbox:
          CaptureInboxView(model: self.captureInboxModel, categoryModel: self.categoryModel)
        }
      }
    }
    // 모두 NavigationStack 에 붙여 둔다. 화면을 push 해도 이 View 는 계층에 남아 인덱싱이 이어지고 신호를 넘긴다.
    .task { await self.model.onAppear() }
    // 대표 썸네일 로더. push 로 카드가 사라져도 읽는 중인 것·읽은 것을 잃지 않고, push 동안 바뀐 대표도 읽는다.
    .task { await self.coverModel.onAppear() }
    .onChange(of: self.model.coverIDs, initial: true) {
      self.coverModel.coversChanged(self.model.coverIDs)
    }
    .onChange(of: self.model.storeRevision) {
      self.categoryModel.libraryStoreChanged()
      self.gifticonListModel.libraryStoreChanged()
      self.receiptListModel.libraryStoreChanged()
      self.captureActionsModel.libraryStoreChanged()
      self.tripListModel.libraryStoreChanged()
      self.tripDetailModel.libraryStoreChanged()
      self.searchModel.libraryStoreChanged()
      self.cleanupModel.libraryStoreChanged()
      self.captureInboxModel.libraryStoreChanged()
    }
    // 장소 캐시를 읽는 화면만 다시 읽는다. 닫혀 있으면 각 Model 이 버린다.
    .onChange(of: self.model.placeRevision) {
      self.tripListModel.libraryStoreChanged()
      self.tripDetailModel.libraryStoreChanged()
      self.searchModel.libraryStoreChanged()
    }
    // 상세를 닫은 뒤 끝난 쓰기도 오른다. 같은 사진을 닫았다 바로 다시 열어 경로의 옛 값을 보이는 상세도 다시 읽어 맞춘다.
    // 사용 여부 쓰기는 `storeRevision` 을 올리지 않으므로, 정리 화면에서 연 상세에서 바꾼 기프티콘이 만료됨 ↔ 사용함 섹션을 옮기도록 정리 화면도 맞춘다.
    .onChange(of: self.captureActionsModel.usageRevision) {
      self.model.gifticonUsageChanged()
      self.gifticonListModel.libraryStoreChanged()
      self.cleanupModel.libraryStoreChanged()
      self.captureActionsModel.libraryStoreChanged()
    }
    // 첫 값도 본다: 화면이 백그라운드에서 만들어지면(BG 작업이 앱을 띄움) 처음부터 멈춘 상태로 두고, 보관함 화면 진입(`onAppear()`)은
    // 첫 `.active` 까지 기다린다(docs/ARCHITECTURE.md §4 인덱싱). 앞에서 켤 때 첫 값은 `.inactive` 이고 `.active` 는 변화로 온다
    // (iOS 27.0 시뮬레이터 실험). `.inactive`(알림 센터를 내림 등)는 멈추지 않는다.
    .onChange(of: self.scenePhase, initial: true) { _, phase in
      switch phase {
      case .active: self.model.sceneBecameActive()
      case .background: self.model.sceneEnteredBackground()
      default: break
      }
    }
    // 첫 값(`.inactive`)은 부르지 않는다. 시작 때 오는 `.active` 변화는 여기서도 불리지만 같은 날짜라 다시 계산만 한다.
    // 백그라운드(잠금 포함) 동안의 날짜 변경도 여기서 덮는다.
    .onChange(of: self.scenePhase) { _, phase in
      guard phase == .active else { return }
      self.gifticonListModel.dayChanged()
      self.receiptListModel.dayChanged()
      self.captureActionsModel.dayChanged()
      self.tripListModel.dayChanged()
      self.tripDetailModel.dayChanged()
      self.searchModel.dayChanged()
      self.cleanupModel.dayChanged()
      self.captureInboxModel.dayChanged()
    }
    // 아래 알림 모두 백그라운드 큐에서 post 해도 `.onReceive` 의 action 은 메인에서 돈다(iOS 26.5 시뮬레이터 실험으로 확인).
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      self.dayChanged()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      self.dayChanged()
    }
    // 이 알림이 앱 복귀보다 먼저 오는지 확인하지 못해 복귀(`sceneBecameActive`)와 둘 다 계기로 둔다.
    .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
      self.model.localeChanged()
    }
  }

  /// 앱이 뒤에 있으면(BG 작업이 깨운 프로세스) 넘기지 않는다. 앞으로 올 때 `.active` 변화가 아홉 Model 을 다시 맞춘다.
  private func dayChanged() {
    guard self.model.isSceneActive else { return }
    self.model.dayChanged()
    self.gifticonListModel.dayChanged()
    self.receiptListModel.dayChanged()
    self.captureActionsModel.dayChanged()
    self.tripListModel.dayChanged()
    self.tripDetailModel.dayChanged()
    self.searchModel.dayChanged()
    self.cleanupModel.dayChanged()
    self.captureInboxModel.dayChanged()
  }

  private var limitedAccessBanner: some View {
    HStack(spacing: 12) {
      Label("선택한 사진만 분류합니다", systemImage: "photo.badge.checkmark")
        .font(.subheadline)
      Spacer()
      Button("사진 더 선택") {
        Task { await self.model.selectMorePhotosTapped() }
      }
      .buttonStyle(.snapSecondary)
      .controlSize(.small)
      .font(.subheadline)
    }
    .padding()
    .background(SnapColor.card, in: .rect(cornerRadius: 20))
    .padding(.horizontal)
  }
}

/// 검색 중이면 `SearchResultsView`, 아니면 카테고리 카드 격자(`content`)를 보인다.
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
  var expiryReminderSection: some View {
    HStack {
      Label("기프티콘 만료일이 다가오면 알려 드려요", systemImage: "bell")
        .font(.subheadline)
      Spacer()
      Button("만료 알림 받기") {
        Task { await self.model.notificationsTapped() }
      }
      .buttonStyle(.snapSecondary)
      .controlSize(.small)
      .font(.subheadline)
    }
    .snapCard()
  }

  /// 알림을 거부했고 지금 예약할 알림이 있을 때만 보인다 (docs/ARCHITECTURE.md §4 만료 알림).
  var notificationSettingsSection: some View {
    HStack {
      Label("만료 알림이 꺼져 있어요", systemImage: "bell.slash")
        .font(.subheadline)
      Spacer()
      Button("설정에서 알림 켜기") {
        Task { await self.model.notificationSettingsTapped() }
      }
      .buttonStyle(.snapSecondary)
      .controlSize(.small)
      .font(.subheadline)
    }
    .snapCard()
  }
}

/// 카테고리 이름과 색 칸 아이콘. 칸은 큰 글씨를 따라 커진다.
struct CategoryLabel: View {
  let category: ImageCategory

  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30

  var body: some View {
    Label {
      Text(self.category.title)
    } icon: {
      IconTile(self.category.glyph, size: self.iconSize, scale: .compact)
    }
  }
}
