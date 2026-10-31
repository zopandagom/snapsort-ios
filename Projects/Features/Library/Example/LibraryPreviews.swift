import BackgroundIndexingTesting
import Core
import Foundation
import IndexingTesting
import LibraryFeature
import NotificationTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreTesting
import SwiftUI
import TripPlaceTesting

// 보관함 화면·카테고리 화면·사진 상세 Preview. 데모 앱 본문은 LibraryFeatureExampleApp.swift 에 있다.

/// 같은 저장소를 읽는 Model 들로 보관함 화면을 만든다. 카테고리 카드를 누르면 그 저장소로 카테고리 화면이 열린다.
@MainActor
private func libraryPreview(
  photoLibrary: PhotoLibraryClientFake,
  indexing: IndexingClientFake?,
  photoStore: PhotoStoreClientFake?,
  notification: NotificationClientFake?
) -> LibraryView {
  let model = LibraryModel(
    photoLibrary: photoLibrary,
    indexing: indexing,
    photoStore: photoStore,
    notification: notification,
    widgetTimeline: nil,
    tripPlace: TripPlaceClientFake(),
    backgroundIndexing: BackgroundIndexingClientFake()
  )
  // 보관함 화면 진입은 첫 `.active` 까지 기다린다. 캔버스가 scenePhase 를 어떻게 주는지와 관계없이 바로 보이게 미리 앞으로 둔다
  // (Fake 라 저장소 출입과 무관하다).
  model.sceneBecameActive()
  return LibraryView(
    model: model,
    coverModel: LibraryCoverModel(photoLibrary: photoLibrary),
    categoryModel: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore),
    gifticonListModel: GifticonListModel(photoStore: photoStore),
    receiptListModel: ReceiptListModel(photoStore: photoStore),
    captureActionsModel: captureActionsPreviewModel(photoStore: photoStore),
    tripListModel: TripListModel(photoLibrary: photoLibrary, photoStore: photoStore),
    tripDetailModel: TripDetailModel(photoStore: photoStore, map: PreviewTrips.map()),
    searchModel: SearchModel(photoStore: photoStore),
    cleanupModel: CleanupModel(photoLibrary: photoLibrary, photoStore: photoStore, findsSimilarPhotos: true),
    captureInboxModel: CaptureInboxModel(photoLibrary: photoLibrary, photoStore: photoStore)
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

#Preview("분류 준비 중") {
  // 첫 진행률을 보내지 않고 계속 돌아 "준비 중" 카드가 남는다.
  libraryPreview(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake(progress: [], finishesAfterProgress: false),
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
