import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
@testable import LibraryFeature

/// 정리 화면·최근 스크린샷 테스트의 공통 준비. 지금 시각은 Asia/Seoul 2026-10-24 09:00 으로 고정한다.
/// 기프티콘 기본 데이터: 어제 만료(`expired`)·열흘 전 만료이지만 만료일이 추정(`estimated`)·오늘 만료(`today`)·내일 만료(`soon`)·
/// 추출 대기(`pending`)·사용함(`used`). 스크린샷 기본 데이터: 기간 안 셋(`s1` 최신 → `s3`), 기간 밖 하나(`old`), 스크린샷이 아닌 사진(`photo`).
@MainActor
enum CleanupFixture {
  static let now = Date.seoul(2026, 10, 24, hour: 9)

  static func clock() -> TestClock {
    TestClock(now: CleanupFixture.now, calendar: .seoul)
  }

  static func model(
    library: PhotoLibraryClientFake = CleanupFixture.library(),
    photoStore: PhotoStoreClientFake?,
    findsSimilarPhotos: Bool = false,
    clock: TestClock = CleanupFixture.clock()
  ) -> CleanupModel {
    CleanupModel(
      photoLibrary: library,
      photoStore: photoStore,
      findsSimilarPhotos: findsSimilarPhotos,
      calendar: { clock.calendar },
      now: { clock.now }
    )
  }

  static func inboxModel(
    library: PhotoLibraryClientFake = CleanupFixture.library(),
    photoStore: PhotoStoreClientFake?,
    clock: TestClock = CleanupFixture.clock()
  ) -> CaptureInboxModel {
    CaptureInboxModel(photoLibrary: library, photoStore: photoStore, calendar: { clock.calendar }, now: { clock.now })
  }

  /// 보관함에 `ids` 가 있는 대역. 지울 수 있으려면 보관함에 있어야 한다.
  static func library(
    containing ids: [String] = CleanupFixture.allIDs,
    state: PhotoAccessState = .authorized,
    deletionErrors: [Int: ImageDeletionError] = [:],
    deletionGate: (@Sendable (Set<ImageAsset.ID>) async -> Void)? = nil
  ) -> PhotoLibraryClientFake {
    PhotoLibraryClientFake(
      currentState: state,
      imageAssets: ids.map { .stub(id: $0) },
      deletionErrors: deletionErrors,
      deletionGate: deletionGate
    )
  }

  static let gifticonIDs = ["expired", "estimated", "today", "soon", "pending", "used"]
  static let screenshotIDs = ["s1", "s2", "s3", "old", "photo"]
  static let allIDs = CleanupFixture.gifticonIDs + CleanupFixture.screenshotIDs

  static func gifticons() -> [IndexedImage] {
    [
      .gifticon(id: "expired", creationDate: .seoul(2026, 9, 1, hour: 12), expiryDate: .date(2026, 10, 23)),
      .gifticon(
        id: "estimated",
        creationDate: .seoul(2026, 9, 2, hour: 12),
        expiryDate: .date(2026, 10, 14),
        modelFilledFields: [.expiryDate]
      ),
      .gifticon(id: "today", creationDate: .seoul(2026, 9, 3, hour: 12), expiryDate: .date(2026, 10, 24)),
      .gifticon(id: "soon", creationDate: .seoul(2026, 9, 4, hour: 12), expiryDate: .date(2026, 10, 25)),
      .pendingGifticon(id: "pending"),
      .gifticon(id: "used", creationDate: .seoul(2026, 9, 5, hour: 12), expiryDate: .date(2026, 12, 1)),
    ]
  }

  static func screenshots() -> [IndexedImage] {
    [
      .screenshot(id: "s1", .seoul(2026, 10, 23, hour: 12)),
      .screenshot(id: "s2", .seoul(2026, 10, 20, hour: 12)),
      .screenshot(id: "s3", .seoul(2026, 10, 1, hour: 12)),
      .screenshot(id: "old", .seoul(2026, 9, 24, hour: 23)),
      .dated(id: "photo", .seoul(2026, 10, 22, hour: 12)),
    ]
  }

  static func store(
    extra: [IndexedImage] = [],
    gifticonsErrors: [Int: PhotoStoreError] = [:],
    onGifticons: @escaping @Sendable (Int) async -> Void = { _ in },
    captureInboxErrors: [Int: PhotoStoreError] = [:],
    onCaptureInboxScreenshots: @escaping @Sendable (Int) async -> Void = { _ in },
    captureInboxKeepError: PhotoStoreError? = nil,
    onKeepInCaptureInbox: @escaping @Sendable (Int) async -> Void = { _ in },
    similarPhotoEntriesErrors: [Int: PhotoStoreError] = [:],
    onSimilarPhotoEntries: @escaping @Sendable (Int) async -> Void = { _ in }
  ) -> PhotoStoreClientFake {
    PhotoStoreClientFake(
      images: CleanupFixture.gifticons() + CleanupFixture.screenshots() + extra,
      usedIDs: ["used"],
      gifticonsErrors: gifticonsErrors,
      onGifticons: onGifticons,
      similarPhotoEntriesErrors: similarPhotoEntriesErrors,
      onSimilarPhotoEntries: onSimilarPhotoEntries,
      captureInboxErrors: captureInboxErrors,
      onCaptureInboxScreenshots: onCaptureInboxScreenshots,
      captureInboxKeepError: captureInboxKeepError,
      onKeepInCaptureInbox: onKeepInCaptureInbox
    )
  }
}

extension IndexedImage {
  /// 글자를 읽지 않은 스크린샷.
  static func screenshot(id: String, _ creationDate: Date?) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: creationDate, isScreenshot: true),
      labels: [],
      textRecognition: .notNeeded,
      categories: [.other]
    )
  }
}

extension CleanupContent {
  var sections: CleanupSections? {
    guard case let .loaded(sections) = self else { return nil }
    return sections
  }

  /// 섹션의 후보 식별자, 화면 순서. 섹션이 없으면 빈 배열, 읽기 전이나 실패면 nil.
  func ids(_ kind: CleanupSection.Kind) -> [ImageAsset.ID]? {
    self.sections.map { sections in
      sections.sections.first { $0.kind == kind }?.candidates.map(\.id) ?? []
    }
  }

  var candidateIDs: Set<ImageAsset.ID>? {
    self.sections?.candidateIDs
  }
}

extension CaptureInboxContent {
  var ids: [ImageAsset.ID]? {
    guard case let .loaded(assets) = self else { return nil }
    return assets.map(\.id)
  }
}

extension CleanupModel {
  /// 화면을 새 방문으로 열고 처음 읽기가 끝날 때까지 기다린다. 돌려준 Task 를 취소하면 화면이 닫힌 것이다.
  func open(visit: UUID = UUID()) async -> Task<Void, Never> {
    let task = Task { await self.onAppear(visit: visit) }
    await waitUntil { self.visit == visit && self.content != .loading }
    return task
  }
}

extension CaptureInboxModel {
  /// 화면을 새 방문으로 열고 처음 읽기가 끝날 때까지 기다린다. 돌려준 Task 를 취소하면 화면이 닫힌 것이다.
  func open(visit: UUID = UUID()) async -> Task<Void, Never> {
    let task = Task { await self.onAppear(visit: visit) }
    await waitUntil { self.visit == visit && self.content != .loading }
    return task
  }
}
