import Core
import Foundation
import IndexingInterface
import IndexingTesting
import LibraryFeature
import NotificationInterface
import NotificationTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
/// 카테고리를 연 채 아래 버튼으로 저장소를 바꾸면, 인덱서가 진행률을 보낸 것처럼 카테고리 화면이 다시 읽는다.
@main
struct LibraryFeatureExampleApp: App {
  private static let photoStore = PhotoStoreClientFake.previewClassified()
  /// 계속 분석 중이라 버튼으로 진행률을 더 보낼 수 있다.
  private static let indexing = IndexingClientFake(
    progress: IndexingClientFake.previewInProgress.progress,
    finishesAfterProgress: false
  )

  /// 알림 권한을 정하기 전이라 "만료 알림 받기" 버튼이 보이고, 누르면 허용된 것처럼 버튼이 사라진다.
  @State private var model = LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: Self.indexing,
    photoStore: Self.photoStore,
    notification: NotificationClientFake.previewNotDetermined()
  )
  @State private var categoryModel = CategoryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    photoStore: Self.photoStore
  )
  /// 지금까지 더한 새 사진 수. 데모 버튼의 다음 식별자를 정한다.
  @State private var addedCount = 0

  var body: some Scene {
    WindowGroup {
      LibraryView(model: self.model, categoryModel: self.categoryModel)
        .overlay(alignment: .bottom) {
          HStack {
            Button("새 사진 추가") {
              Task { await self.addNewestPhoto() }
            }
            Button("최신 사진 지우기") {
              Task { await self.deleteNewestPhoto() }
            }
          }
          .buttonStyle(.borderedProminent)
          .font(.caption)
          .padding()
        }
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

  /// "사진 더 선택"을 누르면 고른 사진이 늘어난 것처럼 보이게 한다.
  static let previewLimited = PhotoLibraryClientFake(
    currentState: .limited,
    imageAssets: .stubs(count: 12),
    imageAssetsAfterPicker: .stubs(count: 30)
  )
}

extension IndexingClientFake {
  /// 128장 중 40장을 분석하고 2장을 미룬 상태로 계속 분석 중이다.
  static let previewInProgress = IndexingClientFake(
    progress: [IndexingProgress(totalCount: 128, indexedCount: 40, skippedCount: 2)],
    finishesAfterProgress: false
  )

  /// 128장 중 40장에서 멈춘 상태. "다시 시도"를 누르면 다시 시작했다가 또 멈춘다.
  static let previewStopped = IndexingClientFake(
    progress: [IndexingProgress(totalCount: 128, indexedCount: 40, skippedCount: 0)]
  )

  /// 모두 분류하고 캡처 34장 중 12장의 글자를 읽었고 1장은 읽지 못해 미룬 상태로 계속 읽는 중이다.
  static let previewRecognizingText = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: 128,
      indexedCount: 126,
      skippedCount: 2,
      pendingTextCount: 21,
      recognizedTextCount: 12,
      skippedTextCount: 1
    )],
    finishesAfterProgress: false
  )

  /// 글자를 읽다가 21장을 남기고 멈춘 상태.
  static let previewTextStopped = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: 128,
      indexedCount: 128,
      skippedCount: 0,
      pendingTextCount: 21,
      recognizedTextCount: 12
    )]
  )

  /// 모두 분석해 진행률을 숨기고, 읽지 못해 미룬 8장(1단계 5장 + 글자 3장)만 안내하는 상태.
  static let previewFinished = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: 128,
      indexedCount: 123,
      skippedCount: 5,
      recognizedTextCount: 30,
      skippedTextCount: 3
    )],
    finishesAfterProgress: false
  )
}

extension NotificationClientFake {
  /// 권한을 정하기 전. 요청하면 허용된다. Preview 마다 새로 만들어 서로 상태를 나누지 않는다.
  static func previewNotDetermined() -> NotificationClientFake {
    NotificationClientFake(authorization: .notDetermined, authorizationAfterRequest: .authorized)
  }

  static func previewAuthorized() -> NotificationClientFake {
    NotificationClientFake(authorization: .authorized)
  }
}

extension PhotoStoreClientFake {
  /// 정보형·사진형 카테고리와 여행이 섞인 분류 결과(`PreviewPhotos`). Preview 마다 새로 만들어 서로 상태를 나누지 않는다.
  /// - Parameters:
  ///   - hasUpcomingExpiry: 참이면 기프티콘이 오늘부터 10일 뒤 만료되어 만료 알림을 예약할 수 있다.
  ///     거짓이면 기프티콘의 만료일을 찾지 못한 것으로 둔다.
  ///   - assetsErrors: 카테고리 화면 읽기(`assets(in:)`)의 호출 번호별 실패.
  static func previewClassified(
    hasUpcomingExpiry: Bool = true,
    assetsErrors: [Int: PhotoStoreError] = [:]
  ) -> PhotoStoreClientFake {
    let expiryDate = hasUpcomingExpiry ? LocalDate(Date(), calendar: .current).addingDays(10) : nil
    let images = PreviewPhotos.counts.flatMap { category, count in
      (0 ..< count).map { index in
        // 기프티콘 추출 값은 글자를 읽은 기프티콘에만 담긴다(`IndexedImage` init).
        IndexedImage(
          asset: .stub(
            id: PreviewPhotos.id(category, index),
            creationDate: PreviewPhotos.creationDate(index: index, count: count)
          ),
          labels: [],
          textRecognition: category == .gifticon ? .recognized([]) : .notNeeded,
          categories: [category],
          gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: nil)
        )
      }
    }
    let trip = Trip(
      assetIDs: [],
      startDate: Date(timeIntervalSince1970: 0),
      endDate: Date(timeIntervalSince1970: 86400),
      center: Coordinate(latitude: 33.5, longitude: 126.5)
    )
    return PhotoStoreClientFake(images: images, trips: [trip, trip], assetsErrors: assetsErrors)
  }
}

/// 같은 저장소를 읽는 두 Model 로 보관함 화면을 만든다. 카테고리 줄을 누르면 그 저장소로 카테고리 화면이 열린다.
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
    categoryModel: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore)
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
      asset: .stub(id: PreviewPhotos.id(.food, 0), creationDate: Date())
    )
  }
}

#Preview("상세 - 실패") {
  NavigationStack {
    PhotoDetailView(
      model: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewFailing, photoStore: nil),
      asset: .stub(id: PreviewPhotos.id(.food, 0), creationDate: Date())
    )
  }
}
