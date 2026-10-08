import PhotoLibraryInterface
import Photos
import Testing
@testable import PhotoLibraryImpl

struct PhotoLibraryClientImplTests {
  @Test(
    "PHAuthorizationStatus 를 PhotoAccessState 로 변환한다",
    arguments: [
      (PHAuthorizationStatus.authorized, PhotoAccessState.authorized),
      (.limited, .limited),
      (.notDetermined, .notDetermined),
      (.denied, .denied),
      (.restricted, .denied),
    ]
  )
  func mapsAuthorizationStatus(status: PHAuthorizationStatus, expected: PhotoAccessState) {
    #expect(PhotoLibraryClientImpl.map(status) == expected)
  }

  @Test(
    "이미지가 추가·삭제됐거나 증분 정보가 없을 때만 변경을 알린다",
    arguments: [
      (false, 0, 0, true),
      (true, 1, 0, true),
      (true, 0, 1, true),
      (true, 0, 0, false),
    ]
  )
  func notifiesOnlyWhenImagesAddedOrRemoved(
    hasIncrementalChanges: Bool,
    insertedCount: Int,
    removedCount: Int,
    expected: Bool
  ) {
    let shouldNotify = ImageChangeObserver.shouldNotify(
      hasIncrementalChanges: hasIncrementalChanges,
      insertedCount: insertedCount,
      removedCount: removedCount
    )

    #expect(shouldNotify == expected)
  }
}
