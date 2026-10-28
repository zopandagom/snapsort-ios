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
/// 그 이미지는 모두 스크린샷이라 최근 스크린샷 화면에도 든다. 여기에 최근 스크린샷 기간 안팎의 스크린샷을 더한다.
/// 보관함 대역은 데모 이미지를 갖고 있어 삭제가 실제처럼 증분 변경을 보낸다. CU 한 장은 일부러 보관함에서 빼, "이미 없어 건너뜀" 안내를 본다.
/// 비슷한 사진(`similarPhotos`)은 Fake 벡터를 단 카메라 사진이다: 묶음 A(3장, 2초 간격, 가운데 장이 가장 커서 남김),
/// 묶음 B(2장, 크기가 같아 최신이 남김), 묶음 C(20장, 2초 간격, 크기가 같아 최신이 남김. 후보가 화면 여러 개 밖까지 이어져
/// 체크 원 끌기의 장거리 자동 스크롤을 본다), 묶음 A 바로 뒤에 찍었지만 거리가 먼 1장(묶이지 않음), 같은 시각의 스크린샷 1장(대상 아님),
/// 벡터가 없는 대상 사진 3장(아직 비교하지 않은 3장). 벡터는 원소 하나만 바꿔 거리를 그 차이로 맞춘다.
enum PreviewCleanup {
  /// 오늘부터 며칠 전에 찍은 스크린샷. 30일(오늘 포함) 밖은 최근 스크린샷 화면에 나오지 않는다.
  static let screenshotDaysAgo = [0, 2, 5, 9, 14, 21, 29, 35, 60]
  /// 보관함 대역에서 뺀 기프티콘 데모 번호(CU, 만료됨·기본 선택).
  static let missingGifticonIndex = 4

  static func id(_ index: Int) -> ImageAsset.ID {
    "cleanup-shot-\(index)"
  }

  /// 비슷한 사진 데모 한 장: 몇 초 전에 찍었는지, 벡터 첫 원소(nil 이면 벡터 없음), 크기, 스크린샷 여부.
  struct SimilarPhoto {
    let secondsAgo: TimeInterval
    let featureValue: Float?
    var pixelWidth = 4032
    var pixelHeight = 3024
    var isScreenshot = false
  }

  static let similarPhotoSamples: [SimilarPhoto] = [
    // 묶음 A: 두 시간 전 2초 간격. 이웃 거리 0.1, 첫 장과 0.2.
    SimilarPhoto(secondsAgo: 7200, featureValue: 0),
    SimilarPhoto(secondsAgo: 7198, featureValue: 0.1, pixelWidth: 5712, pixelHeight: 4284),
    SimilarPhoto(secondsAgo: 7196, featureValue: 0.2),
    // 묶음 A 의 5초 뒤지만 거리 0.8 이라 끊기고, 혼자라 묶음이 아니다.
    SimilarPhoto(secondsAgo: 7191, featureValue: 1.0),
    // 같은 때의 스크린샷은 대상이 아니다.
    SimilarPhoto(secondsAgo: 7195, featureValue: 0.15, isScreenshot: true),
    // 묶음 B: 하루 전 3초 간격. 크기가 같아 최신이 남김.
    SimilarPhoto(secondsAgo: 86400, featureValue: 3.0),
    SimilarPhoto(secondsAgo: 86397, featureValue: 3.05),
    // 아직 비교하지 않은 대상 사진.
    SimilarPhoto(secondsAgo: 3 * 86400, featureValue: nil),
    SimilarPhoto(secondsAgo: 3 * 86400 - 1, featureValue: nil),
    SimilarPhoto(secondsAgo: 3 * 86400 - 2, featureValue: nil),
  ] + PreviewCleanup.longGroupSamples

  /// 묶음 C: 이틀 전 2초 간격 20장. 이웃 거리 0.02, 첫 장과 최대 0.38. 크기가 같아 최신이 남김.
  static let longGroupSamples: [SimilarPhoto] = (0 ..< 20).map { index in
    SimilarPhoto(secondsAgo: 2 * 86400 - TimeInterval(index * 2), featureValue: 6 + Float(index) * 0.02)
  }

  static func similarID(_ index: Int) -> ImageAsset.ID {
    "cleanup-similar-\(index)"
  }

  static var imageIDs: [ImageAsset.ID] {
    self.screenshotDaysAgo.indices.map { self.id($0) } + self.similarPhotoSamples.indices.map { self.similarID($0) }
  }

  /// 정리 데모가 저장소에 더하는 이미지: 최근 스크린샷 화면의 스크린샷과 비슷한 사진.
  static func images(now: Date) -> [IndexedImage] {
    self.screenshots(now: now) + self.similarPhotos(now: now)
  }

  static func similarPhotos(now: Date) -> [IndexedImage] {
    self.similarPhotoSamples.enumerated().map { index, sample in
      IndexedImage(
        asset: .stub(
          id: self.similarID(index),
          creationDate: now.addingTimeInterval(-sample.secondsAgo),
          pixelWidth: sample.pixelWidth,
          pixelHeight: sample.pixelHeight,
          isScreenshot: sample.isScreenshot
        ),
        labels: [],
        textRecognition: .notNeeded,
        categories: [.other],
        featurePrint: sample.featureValue.flatMap(self.featurePrint)
      )
    }
  }

  /// 첫 원소만 `value` 이고 나머지는 0 인 벡터. 두 벡터의 거리는 첫 원소 차이다.
  private static func featurePrint(_ value: Float) -> ImageFeaturePrint? {
    var values = [Float](repeating: 0, count: ImageFeaturePrint.elementCount)
    values[0] = value
    return ImageFeaturePrint(values: values)
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
    return .stubs(count: 128) + gifticons + self.images(now: now).map(\.asset)
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
      model: CleanupModel(photoLibrary: photoLibrary, photoStore: photoStore, findsSimilarPhotos: true),
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
    extraImages: PreviewCleanup.images(now: Date())
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

#Preview("최근 스크린샷 - 스크린샷") {
  captureInboxPreview()
}

#Preview("최근 스크린샷 - 비어 있음") {
  captureInboxPreview(photoStore: PhotoStoreClientFake())
}

#Preview("최근 스크린샷 - 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 목록이 보인다.
  captureInboxPreview(photoStore: cleanupPreviewStore(captureInboxErrors: [0: .failed]))
}

#Preview("최근 스크린샷 - 제한 접근") {
  captureInboxPreview(photoLibrary: PhotoLibraryClientFake.previewLimitedClassified)
}
