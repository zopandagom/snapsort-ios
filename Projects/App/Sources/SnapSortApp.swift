import BackgroundIndexingImpl
import ClassifierImpl
import DesignSystem
import Foundation
import ImageAnalysisImpl
import IndexingImpl
import LibraryFeature
import MapImpl
import NotificationImpl
import OnboardingFeature
import PasteboardImpl
import PhotoLibraryImpl
import PhotoStoreImpl
import SwiftUI
import TripPlaceImpl
import WidgetTimelineImpl
#if DEBUG
  import SampleRecorderFeature
#endif

/// 앱의 조립 지점. Client Impl 을 만들어 Feature Model 에 주입한다(다른 조립 지점은 위젯 Extension, docs/ARCHITECTURE.md §2).
@main
struct SnapSortApp: App {
  @State private var onboardingModel: OnboardingModel
  @State private var libraryModel: LibraryModel
  @State private var libraryCoverModel: LibraryCoverModel
  @State private var categoryModel: CategoryModel
  @State private var gifticonListModel: GifticonListModel
  @State private var receiptListModel: ReceiptListModel
  @State private var captureActionsModel: CaptureActionsModel
  @State private var tripListModel: TripListModel
  @State private var tripDetailModel: TripDetailModel
  @State private var searchModel: SearchModel
  @State private var cleanupModel: CleanupModel
  @State private var captureInboxModel: CaptureInboxModel
  #if DEBUG
    /// Debug 빌드 전용 기록 도구 (docs/ARCHITECTURE.md §4 기록 도구).
    @State private var sampleRecorderModel: SampleRecorderModel
  #endif
  init() {
    // 앱이 앞에 있을 때도 만료 알림이 보이게 한다. 알림이 울리기 전에 등록돼 있어야 하므로 가장 먼저 한다
    // (docs/ARCHITECTURE.md §4 만료 알림).
    NotificationClientImpl.registerForegroundPresentation()
    // 내비게이션 바 제목은 UIKit 이라 화면 루트의 `snapTheme()` 이 닿지 않는다.
    SnapNavigationBar.applyRoundedTitles()
    let photoLibrary = PhotoLibraryClientImpl()
    let imageAnalysis = ImageAnalysisClientImpl()
    self._onboardingModel = State(initialValue: OnboardingModel(photoLibrary: photoLibrary))
    // 인덱서가 쓰고 보관함 화면이 읽고 위젯이 읽기 전용으로 여는 같은 저장소다.
    // 저장소를 열지 못하면(디스크 공간 부족, 손상된 저장 파일 등) 분류 없이 보관함만 보여 준다.
    let photoStore = Self.openPhotoStore()
    // 저장소를 옮기거나 처음 만들거나 경량 이전을 한 것은 여기다. 그 전에 위젯이 읽어 "앱을 열어 주세요"가 남았을 수 있어
    // 열기 성공·실패와 관계없이 한 번 다시 읽기를 요청한다(조립 지점의 부수효과, docs/ARCHITECTURE.md §4 만료 임박 위젯).
    let widgetTimeline = WidgetTimelineClientImpl()
    widgetTimeline.reloadExpiryWidget()
    let indexing = photoStore.map { Self.makeIndexing(photoLibrary, imageAnalysis, $0) }
    let map = MapClientImpl()
    // 여행 장소 이름 미리 받기. 분류 1단계를 마친 뒤(글자 읽기와 병렬) 저장된 여행 중심점의 반올림 좌표만 한 번에 하나씩 묻는다
    // (docs/ARCHITECTURE.md §4 위치·지도 원칙 ①). 앱 실행 동안 하나를 보관함 화면과 BG 작업이 함께 써, 빈도 제한(간격·최소 간격·상한·쉼)이
    // 화면 진입과 BG 실행을 넘어 이어진다.
    let tripPlace = photoStore.map { TripPlaceClientImpl(map: map, photoStore: $0) }
    // 앱이 뒤에 있거나 닫혀 있을 때의 분류(BG 처리 작업·사용자가 시작한 계속 처리 작업). 처리 작업 핸들러는 앱이 실행을 마치기 전에 등록해야 해서 여기서 한다
    // (조립 지점의 부수효과, docs/ARCHITECTURE.md §4 인덱싱). 저장소가 없어도 등록한다(예약된 작업이 핸들러 없이 오지 않게).
    let backgroundIndexing = Self.registeredBackgroundIndexing(indexing, tripPlace, widgetTimeline)
    self._libraryModel = State(initialValue: LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: photoStore,
      notification: NotificationClientImpl(),
      widgetTimeline: widgetTimeline,
      tripPlace: tripPlace,
      backgroundIndexing: backgroundIndexing
    ))
    // 보관함 카드의 대표 썸네일. App 이 소유해 보관함 화면에 다시 들어와도(온보딩·기록 도구에서) 읽은 썸네일이 남는다.
    self._libraryCoverModel = State(initialValue: LibraryCoverModel(photoLibrary: photoLibrary))
    // 카테고리 화면도 같은 저장소를 읽는다. 저장소가 없으면 보관함 화면에 카테고리 카드가 없어 열리지 않는다.
    self._categoryModel = State(initialValue: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore))
    self._gifticonListModel = State(initialValue: GifticonListModel(photoStore: photoStore))
    self._receiptListModel = State(initialValue: ReceiptListModel(photoStore: photoStore))
    // 사진 상세의 캡처 행동. 지도 앱 열기·복사는 사용자가 누를 때만 한다.
    self._captureActionsModel = State(initialValue: CaptureActionsModel(
      photoStore: photoStore,
      imageAnalysis: imageAnalysis,
      map: map,
      pasteboard: PasteboardClientImpl()
    ))
    // 여행 폴더. 목록은 지오코딩하지 않고 캐시만 읽는다. 상세는 캐시에 이름이 없을 때만 여행 중심점의 반올림 좌표로 묻는다.
    self._tripListModel = State(initialValue: TripListModel(photoLibrary: photoLibrary, photoStore: photoStore))
    self._tripDetailModel = State(initialValue: TripDetailModel(photoStore: photoStore, map: map))
    // 장소 이름은 캐시만 대조하므로 Map 을 넘기지 않는다.
    self._searchModel = State(initialValue: SearchModel(photoStore: photoStore))
    // 정리 도우미. 사진을 지우는 것은 사용자가 고른 사진을 시스템 확인 창을 거쳐서만 한다.
    // 비슷한 사진은 이 기기에서 특징 벡터를 만들 수 있을 때만 보인다(시뮬레이터는 섹션 없음). init 은 어떤 벡터 요청보다 먼저 돌아
    // 이 값은 기기 지원 여부와 같다(앱이 뒤에 있을 때 넘긴 시한은 섹션에 영향이 없다, docs/ARCHITECTURE.md §4 정리 도우미).
    self._cleanupModel = State(initialValue: CleanupModel(
      photoLibrary: photoLibrary,
      photoStore: photoStore,
      findsSimilarPhotos: imageAnalysis.isFeaturePrintAvailable
    ))
    self._captureInboxModel = State(initialValue: CaptureInboxModel(photoLibrary: photoLibrary, photoStore: photoStore))
    #if DEBUG
      self._sampleRecorderModel = State(initialValue: SampleRecorderModel(
        photoLibrary: photoLibrary,
        imageAnalysis: imageAnalysis
      ))
    #endif
  }

  /// 분류 인덱서. 저장소를 열었을 때만 만든다.
  private static func makeIndexing(
    _ photoLibrary: PhotoLibraryClientImpl,
    _ imageAnalysis: ImageAnalysisClientImpl,
    _ photoStore: PhotoStoreClientImpl
  ) -> IndexingClientImpl {
    IndexingClientImpl(
      photoLibrary: photoLibrary,
      imageAnalysis: imageAnalysis,
      photoStore: photoStore,
      classifier: ClassifierClientImpl()
    )
  }

  /// BG 작업 조정자를 만들고 처리 작업·계속 처리 작업 핸들러를 한 번에 등록한다(같은 식별자 두 번 등록은 앱을 죽인다).
  /// 식별자 이름의 단일 출처는 Tuist `Env` 이고 Info.plist `BGTaskSchedulerPermittedIdentifiers` 를 `TaskIdentifiers` 로 읽는다
  /// (와일드카드가 아닌 값 = 처리 작업, `.*` 로 끝나는 값 = 계속 처리 작업. App Group 이름과 같은 방식). 없는 쪽은 등록·제출하지 않는다.
  private static func registeredBackgroundIndexing(
    _ indexing: IndexingClientImpl?,
    _ tripPlace: TripPlaceClientImpl?,
    _ widgetTimeline: WidgetTimelineClientImpl
  ) -> BackgroundIndexingClientImpl {
    let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
    let identifiers = BackgroundIndexingClientImpl.TaskIdentifiers(permitted: permitted ?? [])
    let backgroundIndexing = BackgroundIndexingClientImpl(
      indexing: indexing,
      tripPlace: tripPlace,
      widgetTimeline: widgetTimeline,
      taskIdentifier: identifiers.processing,
      continuedTaskIdentifier: identifiers.continued
    )
    backgroundIndexing.registerLaunchHandler()
    return backgroundIndexing
  }

  /// 저장 위치는 App Group 컨테이너이고, 옛 위치(Application Support)에만 있으면 열기 전에 옮긴다.
  /// 컨테이너가 없거나(서명 없는 빌드) 옮기지 못하면 옛 위치를 쓴다. 상위 폴더는 저장소 전용이며 기기 백업에서 빠진다
  /// (PhotoStoreClientImpl, docs/ARCHITECTURE.md §4 저장소).
  private static func openPhotoStore() -> PhotoStoreClientImpl? {
    let url = PhotoStoreClientImpl.preparedStoreURL(
      groupContainer: PhotoStoreClientImpl.appGroupContainer(),
      legacyParent: .applicationSupportDirectory
    )
    return try? PhotoStoreClientImpl(url: url)
  }

  var body: some Scene {
    WindowGroup {
      self.root
        // 색·글꼴 기준값(DesignSystem `SnapColor`). 강조색은 UIKit 화면을 위해 `AccentColor` 에셋에도 같은 값이 있다.
        .snapTheme()
    }
  }

  @ViewBuilder
  private var root: some View {
    // 화면 간 흐름은 App 이 정한다. 읽을 수 있는 권한이 생기면 보관함으로 넘어간다.
    if self.onboardingModel.access.canRead {
      #if DEBUG
        SampleRecorderEntry(
          libraryModel: self.libraryModel,
          libraryCoverModel: self.libraryCoverModel,
          categoryModel: self.categoryModel,
          gifticonListModel: self.gifticonListModel,
          receiptListModel: self.receiptListModel,
          captureActionsModel: self.captureActionsModel,
          tripListModel: self.tripListModel,
          tripDetailModel: self.tripDetailModel,
          searchModel: self.searchModel,
          cleanupModel: self.cleanupModel,
          captureInboxModel: self.captureInboxModel,
          sampleRecorderModel: self.sampleRecorderModel
        )
      #else
        LibraryView(
          model: self.libraryModel,
          coverModel: self.libraryCoverModel,
          categoryModel: self.categoryModel,
          gifticonListModel: self.gifticonListModel,
          receiptListModel: self.receiptListModel,
          captureActionsModel: self.captureActionsModel,
          tripListModel: self.tripListModel,
          tripDetailModel: self.tripDetailModel,
          searchModel: self.searchModel,
          cleanupModel: self.cleanupModel,
          captureInboxModel: self.captureInboxModel
        )
      #endif
    } else {
      OnboardingView(model: self.onboardingModel)
    }
  }
}
