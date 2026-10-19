import Core
import Foundation
import IndexingInterface
import IndexingTesting
import LibraryFeature
import NotificationInterface
import NotificationTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI

/// 실제 사진 없이 Library 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
@main
struct LibraryFeatureExampleApp: App {
  /// 알림 권한을 정하기 전이라 "만료 알림 받기" 버튼이 보이고, 누르면 허용된 것처럼 버튼이 사라진다.
  @State private var model = LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: NotificationClientFake.previewNotDetermined()
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
  /// 정보형·사진형 카테고리와 여행이 섞인 분류 결과. Preview 마다 새로 만들어 서로 상태를 나누지 않는다.
  /// - Parameter hasUpcomingExpiry: 참이면 기프티콘이 오늘부터 10일 뒤 만료되어 만료 알림을 예약할 수 있다.
  ///   거짓이면 기프티콘의 만료일을 찾지 못한 것으로 둔다.
  static func previewClassified(hasUpcomingExpiry: Bool = true) -> PhotoStoreClientFake {
    let counts: [(ImageCategory, Int)] = [
      (.gifticon, 7), (.receipt, 12), (.chat, 9), (.document, 4),
      (.food, 21), (.people, 30), (.landscape, 6), (.other, 3),
    ]
    let expiryDate = hasUpcomingExpiry ? LocalDate(Date(), calendar: .current).addingDays(10) : nil
    let images = counts.flatMap { category, count in
      (0 ..< count).map { index in
        // 기프티콘 추출 값은 글자를 읽은 기프티콘에만 담긴다(`IndexedImage` init).
        IndexedImage(
          asset: .stub(id: "\(category.rawValue)-\(index)"),
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
    return PhotoStoreClientFake(images: images, trips: [trip, trip])
  }
}

#Preview("분류 중") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewInProgress,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  ))
}

#Preview("분류 멈춤") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewStopped,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  ))
}

#Preview("글자 읽는 중") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewRecognizingText,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  ))
}

#Preview("글자 읽기 멈춤") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewTextStopped,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  ))
}

#Preview("분류 완료") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: nil
  ))
}

#Preview("제한 접근") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewLimited,
    indexing: nil,
    photoStore: nil,
    notification: nil
  ))
}

#Preview("이미지 없음") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
    indexing: nil,
    photoStore: nil,
    notification: nil
  ))
}

#Preview("알림 허용됨") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(),
    notification: NotificationClientFake.previewAuthorized()
  ))
}

#Preview("만료 예정 없음") {
  LibraryView(model: LibraryModel(
    photoLibrary: PhotoLibraryClientFake.previewAuthorized,
    indexing: IndexingClientFake.previewFinished,
    photoStore: PhotoStoreClientFake.previewClassified(hasUpcomingExpiry: false),
    notification: NotificationClientFake.previewNotDetermined()
  ))
}
