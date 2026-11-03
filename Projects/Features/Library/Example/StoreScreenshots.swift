import BackgroundIndexingTesting
import Core
import DesignSystem
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import IndexingTesting
import LibraryFeature
import MapTesting
import NotificationTesting
import PasteboardTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI
import TripPlaceTesting

/// 스토어 스크린샷 시나리오가 띄울 화면. 실행 인자 `-storeScreen <rawValue>` 로 고르고, 없거나 틀리면 보관함 홈이다.
/// 순서가 스토어 스크린샷 순서다(`scripts/store-screenshots.sh` 의 화면 표와 같다).
enum StoreScreen: String, CaseIterable {
  /// 1. 보관함 홈(곧 만료 띠·카테고리 카드).
  case home
  /// 2. 기프티콘 목록(D-day).
  case gifticons
  /// 3. 기프티콘 상세(바코드·만료일·교환처). 목록의 미사용 섹션 장들을 넘기는 상세로, 첫 장이다.
  case gifticonDetail
  /// 4. 여행 폴더 상세(지도).
  case trip
  /// 5. 검색("제주").
  case search
  /// 6. 정리 도우미.
  case cleanup

  static var current: StoreScreen {
    UserDefaults.standard.string(forKey: "storeScreen").flatMap(StoreScreen.init(rawValue:)) ?? .home
  }
}

/// 2·3·4·6번 화면을 여는 Example 스택의 경로. `LibraryView` 는 경로를 밖에 내놓지 않으므로 같은 Feature View 를 이 스택에 직접 올린다.
enum StoreRoute: Hashable {
  case gifticons
  case gifticonDetail
  case trip
  case cleanup

  /// 화면별 처음 경로. 홈·검색은 `LibraryView` 를 그대로 띄우므로 경로가 없다.
  static func initialPath(for screen: StoreScreen) -> [StoreRoute] {
    switch screen {
    case .home, .search: []
    case .gifticons: [.gifticons]
    case .gifticonDetail: [.gifticons, .gifticonDetail]
    case .trip: [.trip]
    case .cleanup: [.cleanup]
    }
  }
}

/// 스토어 시나리오의 대역. 앱 실행 동안 하나만 만든다.
@MainActor
enum StoreScreenshotClients {
  static let photoStore: PhotoStoreClientFake = {
    let data = StoreScreenshotData.self
    let cameraPhotos = data.withDistantFeaturePrints(data.photoImages() + data.tripPhotos())
    return PhotoStoreClientFake(
      images: data.gifticonImages() + data.captureImages() + cameraPhotos + data.similarImages() + data.recentShots(),
      trips: data.tripValues,
      usedIDs: data.usedIDs,
      places: data.places,
      placesLocaleIdentifier: data.locale.identifier
    )
  }()

  static let photoLibrary = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: StoreScreenshotImages.assets,
    loadImageResults: StoreScreenshotImages.loadImageResults
  )

  /// 처음부터 모두 분류했고 미룬 것이 없다(진행·축하·"읽지 못한" 카드가 모두 안 보인다).
  static let indexing = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: StoreScreenshotImages.assets.count,
      indexedCount: StoreScreenshotImages.assets.count,
      skippedCount: 0
    )],
    finishesAfterProgress: false
  )

  static let map = MapClientFake(openResult: true)
}

/// 스토어 시나리오 루트. 디버그 줄(`FakeRecordView`)·데모 버튼 없이 실제 앱과 같은 Feature View 와 Model 만 그린다.
/// 모든 Model 에 고정 "지금"·달력·로캘을 넣는다(`StoreScreenshotData`).
/// 한계: 2·3·4·6번은 홈에서 줌 전환으로 들어온 상태가 아니라 처음부터 그 화면이고, 스택에는 `StoreRoute` 행선지만 있어
/// 그 화면 안의 칸·줄을 눌러도 아무 데도 가지 않는다(촬영용이라 다루지 않는다).
struct StoreScreenshotRoot: View {
  private let screen = StoreScreen.current
  /// 화면 일시 상태(스택 경로). Model 상태가 아니다.
  @State private var path: [StoreRoute]
  @State private var model: LibraryModel
  @State private var coverModel = LibraryCoverModel(photoLibrary: StoreScreenshotClients.photoLibrary)
  @State private var categoryModel = CategoryModel(
    photoLibrary: StoreScreenshotClients.photoLibrary,
    photoStore: StoreScreenshotClients.photoStore,
    calendar: StoreScreenshotData.calendar
  )
  @State private var gifticonListModel = GifticonListModel(
    photoStore: StoreScreenshotClients.photoStore,
    calendar: { StoreScreenshotData.calendar },
    now: { StoreScreenshotData.now }
  )
  @State private var receiptListModel = ReceiptListModel(
    photoStore: StoreScreenshotClients.photoStore,
    calendar: { StoreScreenshotData.calendar }
  )
  @State private var captureActionsModel = CaptureActionsModel(
    photoStore: StoreScreenshotClients.photoStore,
    imageAnalysis: ImageAnalysisClientFake.storeScreenshots(),
    map: StoreScreenshotClients.map,
    pasteboard: PasteboardClientFake(),
    calendar: { StoreScreenshotData.calendar },
    now: { StoreScreenshotData.now }
  )
  @State private var tripListModel = TripListModel(
    photoLibrary: StoreScreenshotClients.photoLibrary,
    photoStore: StoreScreenshotClients.photoStore,
    calendar: { StoreScreenshotData.calendar },
    locale: { StoreScreenshotData.locale }
  )
  @State private var tripDetailModel = TripDetailModel(
    photoStore: StoreScreenshotClients.photoStore,
    map: StoreScreenshotClients.map,
    calendar: { StoreScreenshotData.calendar },
    locale: { StoreScreenshotData.locale }
  )
  @State private var searchModel = SearchModel(
    photoStore: StoreScreenshotClients.photoStore,
    calendar: { StoreScreenshotData.calendar },
    locale: { StoreScreenshotData.locale }
  )
  @State private var cleanupModel = CleanupModel(
    photoLibrary: StoreScreenshotClients.photoLibrary,
    photoStore: StoreScreenshotClients.photoStore,
    findsSimilarPhotos: true,
    calendar: { StoreScreenshotData.calendar },
    now: { StoreScreenshotData.now }
  )
  @State private var captureInboxModel = CaptureInboxModel(
    photoLibrary: StoreScreenshotClients.photoLibrary,
    photoStore: StoreScreenshotClients.photoStore,
    calendar: { StoreScreenshotData.calendar },
    now: { StoreScreenshotData.now }
  )

  init() {
    self._path = State(initialValue: StoreRoute.initialPath(for: StoreScreen.current))
    self._model = State(initialValue: LibraryModel(
      photoLibrary: StoreScreenshotClients.photoLibrary,
      indexing: StoreScreenshotClients.indexing,
      photoStore: StoreScreenshotClients.photoStore,
      notification: NotificationClientFake.previewAuthorized(),
      widgetTimeline: nil,
      tripPlace: TripPlaceClientFake(),
      backgroundIndexing: BackgroundIndexingClientFake(),
      calendar: StoreScreenshotData.calendar,
      now: { StoreScreenshotData.now },
      locale: { StoreScreenshotData.locale }
    ))
  }

  var body: some View {
    switch self.screen {
    case .home:
      self.library
    case .search:
      // 검색 필드를 누르지 않아도 검색어가 있으면 검색 결과가 보인다(`LibraryView` 의 검색 필드 글자는 이 값에 묶여 있다).
      self.library
        .task { self.searchModel.queryChanged("제주") }
    case .gifticons, .gifticonDetail, .trip, .cleanup:
      NavigationStack(path: self.$path) {
        Color.clear
          .navigationTitle("간직함")
          .snapScreenBackground()
          .navigationDestination(for: StoreRoute.self) { route in
            self.destination(route)
          }
      }
    }
  }

  private var library: some View {
    LibraryView(
      model: self.model,
      coverModel: self.coverModel,
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
  }

  @ViewBuilder
  private func destination(_ route: StoreRoute) -> some View {
    switch route {
    case .gifticons:
      GifticonListView(model: self.gifticonListModel, categoryModel: self.categoryModel)
    case .gifticonDetail:
      PhotoDetailView(
        model: self.categoryModel,
        captureModel: self.captureActionsModel,
        pages: StoreScreenshotData.unusedGifticonIndices.map { index in
          let item = StoreScreenshotData.gifticonItem(index)
          return PhotoPage(asset: item.asset, gifticon: item)
        },
        index: 0
      )
    case .trip:
      TripDetailView(
        model: self.tripDetailModel,
        categoryModel: self.categoryModel,
        trip: StoreScreenshotData.tripValues[StoreScreenshotData.shownTripIndex]
      )
    case .cleanup:
      CleanupView(model: self.cleanupModel, categoryModel: self.categoryModel)
    }
  }
}

/// 스토어 시나리오의 보관함 대역이 갖는 이미지와 읽기 결과. 같은 그림은 여러 장이 나눠 쓴다.
@MainActor
enum StoreScreenshotImages {
  static let assets: [ImageAsset] = {
    let data = StoreScreenshotData.self
    return (data.gifticonImages() + data.captureImages() + data.photoImages() + data.tripPhotos() + data.similarImages()
      + data.recentShots()).map(\.asset)
  }()

  static let loadImageResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = {
    let data = StoreScreenshotData.self
    var results: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = [:]
    func put(_ id: ImageAsset.ID, _ image: CGImage) {
      results[id] = .success(AnalysisImage(cgImage: image, orientation: .up, isLocalFallback: false))
    }
    for index in data.gifticons.indices {
      put(data.gifticonID(index), data.gifticonArtwork(index))
    }
    var captureArt: [StoreScreenshotArtwork.Capture: CGImage] = [:]
    for (index, demo) in data.captures.enumerated() {
      let image = captureArt[demo.art] ?? StoreScreenshotArtwork.capture(demo.art)
      captureArt[demo.art] = image
      put(data.captureID(index), image)
    }
    var photoArt: [StoreScreenshotArtwork.Scene: CGImage] = [:]
    func photo(_ scene: StoreScreenshotArtwork.Scene) -> CGImage {
      let image = photoArt[scene] ?? StoreScreenshotArtwork.photo(scene)
      photoArt[scene] = image
      return image
    }
    for (category, count) in data.photoCounts {
      for index in 0 ..< count {
        let scene = StoreScreenshotImages.scene(category, variant: index % data.variantCount)
        put(data.photoID(category, index), photo(scene))
      }
    }
    for (tripIndex, trip) in data.trips.enumerated() {
      for index in 0 ..< trip.photoCount {
        put(data.tripPhotoID(tripIndex, index), photo(StoreScreenshotImages.tripScene(tripIndex, index)))
      }
    }
    for (groupIndex, group) in data.similarGroups.enumerated() {
      for index in 0 ..< group.count {
        put(data.similarID(groupIndex, index), photo(StoreScreenshotImages.scene(group.category, variant: 5)))
      }
    }
    for index in data.recentShotDaysAgo.indices {
      put(data.id("shot", index), photo(.other(index + 2)))
    }
    return results
  }()

  /// 여행 사진: 그 여행의 풍경 사이에 음식·인물 사진이 섞인다. 4열 격자에서 같은 그림이 세로로 줄 서지 않게 5장 주기다.
  static func tripScene(_ trip: Int, _ index: Int) -> StoreScreenshotArtwork.Scene {
    switch index % 5 {
    case 1: .food(index + trip)
    case 3: .people(index + trip)
    default: .trip(trip, index)
    }
  }

  static func scene(_ category: ImageCategory, variant: Int) -> StoreScreenshotArtwork.Scene {
    switch category {
    case .food: .food(variant)
    case .people: .people(variant)
    case .pet: .pet(variant)
    case .landscape: .landscape(variant)
    default: .other(variant)
    }
  }
}
