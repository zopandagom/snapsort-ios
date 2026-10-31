import BackgroundIndexingInterface
import BackgroundIndexingTesting
import Core
import DesignSystem
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import IndexingTesting
import LibraryFeature
import MapTesting
import NotificationInterface
import NotificationTesting
import PasteboardTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI
import TripPlaceTesting

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
/// 카테고리를 연 채 아래 버튼으로 저장소를 바꾸면, 인덱서가 진행률을 보낸 것처럼 카테고리 화면이 다시 읽는다.
/// 기프티콘 카드에서 기프티콘 목록(`PreviewGifticons.demos` 의 상태들)을, 문서 첫 장에서 주소·번호 행동을 본다.
/// 여행 카드에서 여행 폴더 목록·상세(`PreviewTrips` 의 세 여행)를, 영수증 카드에서 영수증 목록(`PreviewReceipts` 와 여행 영수증)을 본다.
/// "영수증 추출" 버튼은 인덱서의 영수증 소급 추출처럼 추출 대기 영수증에 값을 쓰고 진행률을 보낸다.
/// 쇼핑·대화·지도 카드에서 툴바 묶기 메뉴(쇼핑몰·브랜드·앱·지역별, `PreviewCaptureGroups`)를 보고, "캡처 묶음 추출" 버튼이
/// 추출 대기 캡처에 값을 쓴다(OCR 대기 캡처는 확인 중으로 남는다).
/// 지도·복사·장소 이름·장소 이름 미리 받기는 Fake 라 지도 앱이 열리지 않고 클립보드에 쓰지 않으며 지오코딩하지 않는다.
/// 검색 필드를 누르면 검색 결과(`PreviewSearch` 의 글자 사진, 캡처 묶음 값, 카테고리 이름, 캐시된 여행 장소 이름)를 보고,
/// "글자 사진 추가" 버튼이 글자를 읽은 사진을 최신으로 더한다(열린 검색 화면이 다시 읽는다).
/// 보관함 카테고리 위 "정리 도우미" 카드에서 정리 화면(만료됨·사용함 기프티콘 후보, 정리 시나리오면 비슷한 사진 묶음)과
/// 최근 스크린샷 화면(최근 30일 스크린샷)을 본다.
/// 정리 시나리오(`ExampleScenario.isCleanup`)는 삭제를 흉내 내는 보관함 대역을 쓰고, 지운 이미지를 인덱서처럼 저장소에서 지우고 진행률을 보낸다.
/// 아래 디버그 줄이 Fake 가 받은 마지막 값과 장소 이름 요청 수, 정리 화면이 저장소를 읽은 횟수와 삭제 요청 수를 보인다.
/// 카드의 대표 썸네일은 저장소 대역이 분류 결과로 고른다(기타 1장·반려동물 2장·여행 3개·문서 4장으로 모자이크 1~4칸 배치를 본다).
/// `-scenario homeInCloudOnly` 는 모든 썸네일이 iCloud 에만 있어 카테고리 색 면 + 아이콘으로, `-scenario homeSlowThumbnails` 는
/// 썸네일 읽기가 1.5초 걸려 중립 면 → 사진으로 바뀌는 것을 본다.
/// 시나리오는 실행 인자 `-scenario <이름>` 으로 고른다(`ExampleScenario`).
@main
struct LibraryFeatureExampleApp: App {
  private static let scenario = ExampleScenario.current
  /// `receiptEmpty` 는 빈 저장소다(앱 루트가 빈 영수증 목록).
  private static let photoStore = Self.scenario == .receiptEmpty
    ? PhotoStoreClientFake()
    : PhotoStoreClientFake.previewClassified(
      includesGifticons: Self.scenario != .gifticonEmpty,
      gifticonsErrors: Self.scenario == .gifticonFailing ? [0: .failed] : [:],
      includesTrips: Self.scenario != .tripEmpty,
      tripsErrors: Self.scenario == .tripStoreFailing ? [0: .failed] : [:],
      receiptsErrors: Self.scenario == .receiptFailing ? [0: .failed] : [:],
      captureGroupItemsErrors: Self.scenario == .captureGroupFailing ? [0: .failed] : [:],
      allReceiptsChecking: Self.scenario == .receiptChecking,
      searchEntriesErrors: Self.scenario == .searchFailing ? [0: .failed] : [:],
      onSearchEntries: Self.searchHook,
      extraImages: Self.scenario.isCleanup ? PreviewCleanup.images(now: Date()) : []
    )
  /// `searchSlow` 는 검색 목록 읽기가 1.5초 걸린다.
  private static let searchHook: @Sendable (Int) async -> Void = if Self.scenario == .searchSlow {
    { _ in try? await Task.sleep(for: .seconds(1.5)) }
  } else {
    { _ in }
  }

  private static let photoLibrary = if Self.scenario == .limited {
    PhotoLibraryClientFake.previewLimitedClassified
  } else if Self.scenario == .homeInCloudOnly {
    PhotoLibraryClientFake.previewHomeInCloudOnly
  } else if Self.scenario == .homeSlowThumbnails {
    PhotoLibraryClientFake.previewSlowThumbnails
  } else if Self.scenario.isCleanup {
    PhotoLibraryClientFake.previewCleanup(scenario: Self.scenario)
  } else {
    PhotoLibraryClientFake.previewAuthorized
  }

  /// 계속 분석 중이라 버튼으로 진행률을 더 보낼 수 있다. 시나리오로 준비 중·글자 읽는 중 카드를 본다.
  private static let indexing = IndexingClientFake(progress: Self.indexingProgress, finishesAfterProgress: false)
  private static let indexingProgress: [IndexingProgress] = switch Self.scenario {
  case .indexingPreparing: []
  case .indexingRecognizingText: IndexingClientFake.previewRecognizingText.progress
  default: IndexingClientFake.previewInProgress.progress
  }
  private static let map = PreviewTrips.map(
    failing: Self.scenario == .tripGeocodingFailing,
    openResult: Self.scenario != .mapsUnavailable
  )
  private static let pasteboard = PasteboardClientFake()

  /// 기본은 알림 권한을 정하기 전이라 "만료 알림 받기" 버튼이 보이고, 누르면 허용된 것처럼 버튼이 사라진다.
  @State private var model = LibraryModel(
    photoLibrary: Self.photoLibrary,
    indexing: Self.indexing,
    photoStore: Self.photoStore,
    notification: Self.scenario == .notificationDenied
      ? NotificationClientFake.previewDenied()
      : NotificationClientFake.previewNotDetermined(),
    widgetTimeline: nil,
    tripPlace: TripPlaceClientFake(),
    backgroundIndexing: BackgroundIndexingClientFake(continuedRequestResult: Self.continuedRequestResult)
  )
  /// 진행 카드의 "홈으로 나가도 계속"을 눌렀을 때의 결과. 시나리오로 안내 줄 두 가지를 본다.
  private static let continuedRequestResult: ContinuedIndexingRequestResult = switch Self.scenario {
  case .continuedTryLater: .temporarilyUnavailable
  case .continuedUnavailable: .unavailable
  default: .started
  }
  @State private var coverModel = LibraryCoverModel(photoLibrary: Self.photoLibrary)
  @State private var categoryModel = CategoryModel(photoLibrary: Self.photoLibrary, photoStore: Self.photoStore)
  @State private var gifticonListModel = GifticonListModel(photoStore: Self.photoStore)
  @State private var receiptListModel = ReceiptListModel(photoStore: Self.photoStore)
  @State private var captureActionsModel = CaptureActionsModel(
    photoStore: Self.photoStore,
    imageAnalysis: ImageAnalysisClientFake.previewGifticons(),
    map: Self.map,
    pasteboard: Self.pasteboard
  )
  @State private var tripListModel = TripListModel(photoLibrary: Self.photoLibrary, photoStore: Self.photoStore)
  @State private var tripDetailModel = TripDetailModel(photoStore: Self.photoStore, map: Self.map)
  @State private var searchModel = SearchModel(photoStore: Self.photoStore)
  /// Example 은 시뮬레이터에서 돌지만 Fake 벡터로 비슷한 사진 섹션을 본다(App 시뮬레이터에는 섹션이 없다).
  @State private var cleanupModel = CleanupModel(
    photoLibrary: Self.photoLibrary,
    photoStore: Self.photoStore,
    findsSimilarPhotos: true
  )
  @State private var captureInboxModel = CaptureInboxModel(photoLibrary: Self.photoLibrary, photoStore: Self.photoStore)
  /// 지금까지 더한 새 사진 수. 데모 버튼의 다음 식별자를 정한다.
  @State private var addedCount = 0
  /// 지금까지 더한 글자 사진 수.
  @State private var addedTextCount = 0

  init() {
    // App 과 같은 내비게이션 바 글꼴.
    SnapNavigationBar.applyRoundedTitles()
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if Self.scenario == .receiptEmpty {
          // 보관함은 영수증이 없으면 영수증 카드를 숨겨 빈 목록에 갈 수 없으므로 루트로 띄운다.
          NavigationStack {
            ReceiptListView(model: self.receiptListModel, categoryModel: self.categoryModel)
          }
        } else {
          self.library
            // 정리 삭제가 보관함 변경 → 저장소 삭제 → 진행률로 이어지는 것을 흉내 낸다(실제는 인덱서가 한다).
            .task {
              await simulateIndexerDeletions(
                photoLibrary: Self.photoLibrary,
                photoStore: Self.photoStore,
                indexing: Self.indexing
              )
            }
        }
      }
      // App 루트와 같은 색·글꼴 기준값.
      .snapTheme()
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
    .overlay(alignment: .bottom) {
      VStack(spacing: 4) {
        HStack {
          Button("새 사진 추가") {
            Task { await self.addNewestPhoto() }
          }
          Button("최신 사진 지우기") {
            Task { await self.deleteNewestPhoto() }
          }
          Button("영수증 추출") {
            Task { await self.extractReceipts() }
          }
          Button("캡처 묶음 추출") {
            Task { await self.extractCaptureGroups() }
          }
          Button("글자 사진 추가") {
            Task { await self.addTextPhoto() }
          }
        }
        .buttonStyle(.borderedProminent)
        FakeRecordView(
          map: Self.map,
          pasteboard: Self.pasteboard,
          photoStore: Self.photoStore,
          photoLibrary: Self.photoLibrary
        )
      }
      .font(.caption)
      .padding()
    }
  }

  /// 인덱서가 새 사진을 분류해 저장하고 진행률을 보낸 것처럼 흉내 낸다.
  private func addNewestPhoto() async {
    let id = PreviewPhotos.newPhotoID(self.addedCount)
    self.addedCount += 1
    let image = IndexedImage(
      asset: .stub(id: id, creationDate: Date()),
      labels: [],
      textRecognition: .notNeeded,
      categories: [.people]
    )
    try? await Self.photoStore.save([image])
    Self.indexing.sendProgress(IndexingClientFake.previewInProgress.progress[0])
  }

  /// 사진이 보관함에서 지워져 인덱서가 저장소에서 지우고 진행률을 보낸 것처럼 흉내 낸다.
  private func deleteNewestPhoto() async {
    guard let newest = try? await Self.photoStore.assets(in: .people).first else { return }
    try? await Self.photoStore.delete(ids: [newest.id])
    Self.indexing.sendProgress(IndexingClientFake.previewInProgress.progress[0])
  }

  /// 인덱서가 영수증을 소급 추출해 저장하고 같은 값의 진행률을 보낸 것처럼 흉내 낸다. 추출 대기 행만 바뀐다.
  private func extractReceipts() async {
    try? await Self.photoStore.saveReceipts(PreviewReceipts.extractedValues)
    Self.indexing.sendProgress(IndexingClientFake.previewInProgress.progress[0])
  }

  /// 인덱서가 글자를 읽은 문서 사진을 최신으로 저장하고 진행률을 보낸 것처럼 흉내 낸다. 열려 있는 검색 화면이 다시 읽는다.
  private func addTextPhoto() async {
    let id = PreviewSearch.newImageID(self.addedTextCount)
    self.addedTextCount += 1
    try? await Self.photoStore.save([PreviewSearch.newImage(id: id)])
    Self.indexing.sendProgress(IndexingClientFake.previewInProgress.progress[0])
  }

  /// 인덱서가 쇼핑·대화·지도 캡처를 소급 추출해 저장하고 같은 값의 진행률을 보낸 것처럼 흉내 낸다. 추출 대기 행만 바뀐다.
  private func extractCaptureGroups() async {
    try? await Self.photoStore.saveCaptureGroups(PreviewCaptureGroups.extractedValues)
    Self.indexing.sendProgress(IndexingClientFake.previewInProgress.progress[0])
  }
}
