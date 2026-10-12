import Core
import Foundation
import IndexingInterface
import IndexingTesting
import LibraryFeature
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
@main
struct LibraryFeatureExampleApp: App {
  @State private var model = LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress,
    photoStore: PhotoStoreClientFake.previewClassified()
  )

  var body: some Scene {
    WindowGroup {
      LibraryView(model: self.model)
    }
  }
}

extension PhotoLibraryClientFake {
  static let previewAuthorized = PhotoLibraryClientFake(
    currentState: .authorized,
    imageAssets: .stubs(count: 128)
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

  /// 모두 분석해 진행률을 숨기고, 읽지 못해 미룬 8장만 안내하는 상태.
  static let previewFinished = IndexingClientFake(
    progress: [IndexingProgress(totalCount: 128, indexedCount: 120, skippedCount: 8)],
    finishesAfterProgress: false
  )
}

extension PhotoStoreClientFake {
  /// 정보형·사진형 카테고리와 여행이 섞인 분류 결과. Preview 마다 새로 만들어 서로 상태를 나누지 않는다.
  static func previewClassified() -> PhotoStoreClientFake {
    let counts: [(ImageCategory, Int)] = [
      (.gifticon, 7), (.receipt, 12), (.chat, 9), (.document, 4),
      (.food, 21), (.people, 30), (.landscape, 6), (.other, 3),
    ]
    let images = counts.flatMap { category, count in
      (0 ..< count).map { index in
        IndexedImage(
          asset: .stub(id: "\(category.rawValue)-\(index)"),
          labels: [],
          textLines: nil,
          categories: [category]
        )
      }
    }
    let trip = Trip(
      assetIDs: [],
      startDate: Date(timeIntervalSince1970: 0),
      endDate: Date(timeIntervalSince1970: 86400),
      center: Coordinate(latitude: 33.5, longitude: 126.5)
    )
    return PhotoStoreClientFake(images: images, trips: [trip, trip])
  }
}

#Preview("분류 중") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress,
    photoStore: PhotoStoreClientFake.previewClassified()
  ))
}

#Preview("분류 멈춤") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewStopped,
    photoStore: PhotoStoreClientFake.previewClassified()
  ))
}

#Preview("분류 완료") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified()
  ))
}

#Preview("제한 접근") {
  LibraryView(model: LibraryModel(photoLibrary: PhotoLibraryClientFake.previewLimited, indexing: nil, photoStore: nil))
}

#Preview("이미지 없음") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
    indexing: nil,
    photoStore: nil
  ))
}
