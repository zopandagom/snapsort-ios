import Core
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

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
/// 카테고리를 연 채 아래 버튼으로 저장소를 바꾸면, 인덱서가 진행률을 보낸 것처럼 카테고리 화면이 다시 읽는다.
/// 기프티콘 줄에서 기프티콘 목록(`PreviewGifticons.demos` 의 상태들)을, 문서 첫 장에서 주소·번호 행동을 본다.
/// 여행 줄에서 여행 폴더 목록·상세(`PreviewTrips` 의 세 여행)를, 영수증 줄에서 영수증 목록(`PreviewReceipts` 와 여행 영수증)을 본다.
/// "영수증 추출" 버튼은 인덱서의 영수증 소급 추출처럼 추출 대기 영수증에 값을 쓰고 진행률을 보낸다.
/// 쇼핑·대화·지도 줄에서 툴바 묶기 메뉴(쇼핑몰·브랜드·앱·지역별, `PreviewCaptureGroups`)를 보고, "캡처 묶음 추출" 버튼이
/// 추출 대기 캡처에 값을 쓴다(OCR 대기 캡처는 확인 중으로 남는다).
/// 지도·복사·장소 이름은 Fake 라 지도 앱이 열리지 않고 클립보드에 쓰지 않으며 지오코딩하지 않는다.
/// 검색 필드를 누르면 검색 결과(`PreviewSearch` 의 글자 사진, 캡처 묶음 값, 카테고리 이름, 캐시된 여행 장소 이름)를 보고,
/// "글자 사진 추가" 버튼이 글자를 읽은 사진을 최신으로 더한다(열린 검색 화면이 다시 읽는다).
/// 아래 디버그 줄이 Fake 가 받은 마지막 값과 장소 이름 요청 수를 보인다.
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
      onSearchEntries: Self.searchHook
    )
  /// `searchSlow` 는 검색 목록 읽기가 1.5초 걸린다.
  private static let searchHook: @Sendable (Int) async -> Void = if Self.scenario == .searchSlow {
    { _ in try? await Task.sleep(for: .seconds(1.5)) }
  } else {
    { _ in }
  }

  private static let photoLibrary = Self.scenario == .limited
    ? PhotoLibraryClientFake.previewLimitedClassified
    : PhotoLibraryClientFake.previewAuthorized
  /// 계속 분석 중이라 버튼으로 진행률을 더 보낼 수 있다.
  private static let indexing = IndexingClientFake(
    progress: IndexingClientFake.previewInProgress.progress,
    finishesAfterProgress: false
  )
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
      : NotificationClientFake.previewNotDetermined()
  )
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
  /// 지금까지 더한 새 사진 수. 데모 버튼의 다음 식별자를 정한다.
  @State private var addedCount = 0
  /// 지금까지 더한 글자 사진 수.
  @State private var addedTextCount = 0

  var body: some Scene {
    WindowGroup {
      if Self.scenario == .receiptEmpty {
        // 보관함은 영수증이 없으면 영수증 줄을 숨겨 빈 목록에 갈 수 없으므로 루트로 띄운다.
        NavigationStack {
          ReceiptListView(model: self.receiptListModel, categoryModel: self.categoryModel)
        }
      } else {
        self.library
      }
    }
  }

  private var library: some View {
    LibraryView(
      model: self.model,
      categoryModel: self.categoryModel,
      gifticonListModel: self.gifticonListModel,
      receiptListModel: self.receiptListModel,
      captureActionsModel: self.captureActionsModel,
      tripListModel: self.tripListModel,
      tripDetailModel: self.tripDetailModel,
      searchModel: self.searchModel
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
        FakeRecordView(map: Self.map, pasteboard: Self.pasteboard)
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

extension PhotoLibraryClientFake {
  static let previewAuthorized = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: .stubs(count: 128),
    loadImageResults: PreviewPhotos.loadImageResults
  )

  /// 읽기가 끝나지 않는다. 상세의 불러오는 중을 확인한다.
  static let previewLoadingForever = PhotoLibraryClientFake(
    currentState: .authorized,
    loadImageResults: PreviewPhotos.loadImageResults,
    loadGate: { _ in
      try? await Task.sleep(for: .seconds(3600))
    }
  )

  /// 모든 이미지가 iCloud 에만 있다. 칸의 대체 심볼을 확인한다.
  static let previewInCloudOnly = PhotoLibraryClientFake(
    currentState: .authorized,
    loadImageResults: PreviewPhotos.loadImageResults.mapValues { _ in .failure(.notAvailableLocally) }
  )

  /// 모든 이미지를 읽지 못한다. 상세의 실패를 확인한다.
  static let previewFailing = PhotoLibraryClientFake(
    currentState: .authorized,
    loadImageResults: PreviewPhotos.loadImageResults.mapValues { _ in .failure(.failed) }
  )

  /// 제한 접근이지만 분류 결과의 이미지를 모두 읽을 수 있다. `-scenario limited` 에서 여행 목록 안내를 본다.
  static let previewLimitedClassified = PhotoLibraryClientFake(
    currentState: .limited,
    imageAssets: .stubs(count: 128),
    loadImageResults: PreviewPhotos.loadImageResults
  )

  /// "사진 더 선택"을 누르면 고른 사진이 늘어난 것처럼 보이게 한다.
  static let previewLimited = PhotoLibraryClientFake(
    currentState: .limited,
    imageAssets: .stubs(count: 12),
    imageAssetsAfterPicker: .stubs(count: 30)
  )
}

/// 같은 저장소를 읽는 Model 들로 보관함 화면을 만든다. 카테고리 줄을 누르면 그 저장소로 카테고리 화면이 열린다.
@MainActor
private func libraryPreview(
  photoLibrary: PhotoLibraryClientFake,
  indexing: IndexingClientFake?,
  photoStore: PhotoStoreClientFake?,
  notification: NotificationClientFake?
) -> LibraryView {
  LibraryView(
    model: LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: photoStore,
      notification: notification
    ),
    categoryModel: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore),
    gifticonListModel: GifticonListModel(photoStore: photoStore),
    receiptListModel: ReceiptListModel(photoStore: photoStore),
    captureActionsModel: captureActionsPreviewModel(photoStore: photoStore),
    tripListModel: TripListModel(photoLibrary: photoLibrary, photoStore: photoStore),
    tripDetailModel: TripDetailModel(photoStore: photoStore, map: PreviewTrips.map()),
    searchModel: SearchModel(photoStore: photoStore)
  )
}

#Preview("분류 중") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  )
}

#Preview("분류 멈춤") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewStopped,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  )
}

#Preview("글자 읽는 중") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewRecognizingText,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  )
}

#Preview("글자 읽기 멈춤") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewTextStopped,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  )
}

#Preview("분류 완료") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  )
}

#Preview("제한 접근") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewLimited,
    indexing: nil,
    photoStore: nil,
    notification: nil
  )
}

#Preview("이미지 없음") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
    indexing: nil,
    photoStore: nil,
    notification: nil
  )
}

#Preview("알림 허용됨") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: NotificationClientFake.previewAuthorized()
  )
}

#Preview("보관함 - 알림 거부") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: NotificationClientFake.previewDenied()
  )
}

#Preview("만료 예정 없음") {
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(hasUpcomingExpiry: false),
    notification: NotificationClientFake.previewNotDetermined()
  )
}

#Preview("카테고리 - 빈 카테고리") {
  NavigationStack {
    CategoryView(
      model: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: PhotoStoreClientFake()),
      category: .people
    )
  }
}

#Preview("카테고리 - 저장소 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 격자가 보인다.
  NavigationStack {
    CategoryView(
      model: CategoryModel(
        photoLibrary: PhotoLibraryClientFake.previewAuthorized,
        photoStore: PhotoStoreClientFake.previewClassified(assetsErrors: [0: .failed])
      ),
      category: .food
    )
  }
}

#Preview("카테고리 - iCloud 썸네일") {
  NavigationStack {
    CategoryView(
      model: CategoryModel(
        photoLibrary: PhotoLibraryClientFake.previewInCloudOnly,
        photoStore: PhotoStoreClientFake.previewClassified()
      ),
      category: .food
    )
  }
}

#Preview("상세 - 불러오는 중") {
  NavigationStack {
    PhotoDetailView(
      model: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewLoadingForever, photoStore: nil),
      captureModel: captureActionsPreviewModel(photoStore: nil),
      asset: .stub(id: PreviewPhotos.id(.food, 0), creationDate: Date())
    )
  }
}

#Preview("상세 - 실패") {
  NavigationStack {
    PhotoDetailView(
      model: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewFailing, photoStore: nil),
      captureModel: captureActionsPreviewModel(photoStore: nil),
      asset: .stub(id: PreviewPhotos.id(.food, 0), creationDate: Date())
    )
  }
}
