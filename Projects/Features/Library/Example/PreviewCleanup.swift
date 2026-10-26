import Core
import Foundation
import IndexingTesting
import LibraryFeature
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI

/// Example 의 정리 도우미 데모 (docs/ARCHITECTURE.md §4 정리 도우미).
/// 기프티콘 데모(`PreviewGifticons`)가 만료됨(CU·메가커피, 추정 만료일 파스쿠찌)·사용함(버거킹·맘스터치)·확인 중 후보를 이미 갖고 있고,
/// 그 이미지는 모두 스크린샷이라 캡처 인박스에도 든다. 여기에 인박스 기간 안팎의 스크린샷을 더한다.
/// 보관함 대역은 데모 이미지를 갖고 있어 삭제가 실제처럼 증분 변경을 보낸다. CU 한 장은 일부러 보관함에서 빼, "이미 없어 건너뜀" 안내를 본다.
enum PreviewCleanup {
  /// 오늘부터 며칠 전에 찍은 스크린샷. 30일(오늘 포함) 밖은 인박스에 나오지 않는다.
  static let screenshotDaysAgo = [0, 2, 5, 9, 14, 21, 29, 35, 60]
  /// 보관함 대역에서 뺀 기프티콘 데모 번호(CU, 만료됨·기본 선택).
  static let missingGifticonIndex = 4

  static func id(_ index: Int) -> ImageAsset.ID {
    "cleanup-shot-\(index)"
  }

  static var imageIDs: [ImageAsset.ID] {
    self.screenshotDaysAgo.indices.map { self.id($0) }
  }

  static func screenshots(now: Date) -> [IndexedImage] {
    self.screenshotDaysAgo.enumerated().map { index, daysAgo in
      IndexedImage(
        asset: .stub(
          id: self.id(index),
          creationDate: now.addingTimeInterval(-Double(daysAgo) * 86400),
          isScreenshot: true
        ),
        labels: [],
        textRecognition: .notNeeded,
        categories: [.other]
      )
    }
  }

  /// 보관함 대역이 갖는 이미지: 기존 128장과 정리 데모 이미지(건너뜀을 보이려고 한 장 뺀다).
  static func libraryAssets(now: Date) -> [ImageAsset] {
    let gifticons = PreviewGifticons.images(today: LocalDate(now, calendar: .current), now: now)
      .enumerated()
      .filter { $0.offset != self.missingGifticonIndex }
      .map(\.element.asset)
    return .stubs(count: 128) + gifticons + self.screenshots(now: now).map(\.asset)
  }
}

extension ExampleScenario {
  /// 정리 도우미 데모 데이터(스크린샷)와 삭제를 흉내 내는 보관함 대역을 쓰는 시나리오.
  var isCleanup: Bool {
    switch self {
    case .cleanup, .cleanupDeleteFailing, .cleanupDeleteCancelled, .cleanupDeleteSlow: true
    default: false
    }
  }
}

extension PhotoLibraryClientFake {
  /// 정리 데모용 보관함. 시나리오가 삭제의 첫 요청을 실패·취소시키거나 확인 창이 떠 있는 것처럼 2초 붙잡는다.
  static func previewCleanup(scenario: ExampleScenario) -> PhotoLibraryClientFake {
    let errors: [Int: ImageDeletionError] = switch scenario {
    case .cleanupDeleteFailing: [0: .failed]
    case .cleanupDeleteCancelled: [0: .userCancelled]
    default: [:]
    }
    var gate: (@Sendable (Set<ImageAsset.ID>) async -> Void)?
    if scenario == .cleanupDeleteSlow {
      gate = { _ in try? await Task.sleep(for: .seconds(2)) }
    }
    return PhotoLibraryClientFake(
      currentState: .authorized,
      imageAssets: PreviewCleanup.libraryAssets(now: Date()),
      loadImageResults: PreviewPhotos.loadImageResults,
      deletionErrors: errors,
      deletionGate: gate
    )
  }
}

/// 보관함에서 지운 이미지를 인덱서가 저장소에서 지우고 진행률을 보내는 것을 흉내 낸다. 변경 한 번에 진행률 한 번이다
/// (실제 인덱서의 증분 `apply` 와 같다). 열린 정리 화면이 이 진행률을 한 번의 다시 읽기로 받는지 디버그 줄의 읽은 횟수로 본다.
@MainActor
func simulateIndexerDeletions(
  photoLibrary: PhotoLibraryClientFake,
  photoStore: PhotoStoreClientFake,
  indexing: IndexingClientFake
) async {
  for await change in await photoLibrary.imageChanges() {
    guard case let .incremental(_, removed) = change, !removed.isEmpty else { continue }
    try? await photoStore.delete(ids: Set(removed))
    indexing.sendProgress(IndexingClientFake.previewInProgress.progress[0])
  }
}

@MainActor
private func cleanupPreview(
  photoLibrary: PhotoLibraryClientFake = PhotoLibraryClientFake.previewCleanup(scenario: .cleanup),
  photoStore: PhotoStoreClientFake = cleanupPreviewStore()
) -> some View {
  NavigationStack {
    CleanupView(
      model: CleanupModel(photoLibrary: photoLibrary, photoStore: photoStore),
      categoryModel: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore)
    )
  }
}

@MainActor
private func captureInboxPreview(
  photoLibrary: PhotoLibraryClientFake = PhotoLibraryClientFake.previewCleanup(scenario: .cleanup),
  photoStore: PhotoStoreClientFake = cleanupPreviewStore()
) -> some View {
  NavigationStack {
    CaptureInboxView(
      model: CaptureInboxModel(photoLibrary: photoLibrary, photoStore: photoStore),
      categoryModel: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore)
    )
  }
}

private func cleanupPreviewStore(
  gifticonsErrors: [Int: PhotoStoreError] = [:],
  captureInboxErrors: [Int: PhotoStoreError] = [:]
) -> PhotoStoreClientFake {
  PhotoStoreClientFake.previewClassified(
    gifticonsErrors: gifticonsErrors,
    captureInboxErrors: captureInboxErrors,
    extraImages: PreviewCleanup.screenshots(now: Date())
  )
}

#Preview("정리 - 후보") {
  cleanupPreview()
}

#Preview("정리 - 후보 없음") {
  cleanupPreview(photoStore: PhotoStoreClientFake.previewClassified(includesGifticons: false))
}

#Preview("정리 - 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 목록이 보인다.
  cleanupPreview(photoStore: cleanupPreviewStore(gifticonsErrors: [0: .failed]))
}

#Preview("정리 - 제한 접근") {
  cleanupPreview(photoLibrary: PhotoLibraryClientFake.previewLimitedClassified)
}

#Preview("캡처 인박스 - 스크린샷") {
  captureInboxPreview()
}

#Preview("캡처 인박스 - 비어 있음") {
  captureInboxPreview(photoStore: PhotoStoreClientFake())
}

#Preview("캡처 인박스 - 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 목록이 보인다.
  captureInboxPreview(photoStore: cleanupPreviewStore(captureInboxErrors: [0: .failed]))
}

#Preview("캡처 인박스 - 제한 접근") {
  captureInboxPreview(photoLibrary: PhotoLibraryClientFake.previewLimitedClassified)
}
