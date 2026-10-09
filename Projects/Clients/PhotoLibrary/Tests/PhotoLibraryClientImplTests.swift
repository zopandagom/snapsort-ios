import Core
import CoreLocation
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

  @Test("CLLocation 의 좌표를 Coordinate 로 옮긴다")
  func convertsLocation() {
    let coordinate = PhotoLibraryClientImpl.coordinate(from: CLLocation(latitude: 37.5665, longitude: 126.978))

    #expect(coordinate == Coordinate(latitude: 37.5665, longitude: 126.978))
  }

  @Test(
    "위치가 없거나 좌표가 유효하지 않으면 좌표를 비운다",
    arguments: [
      CLLocation?.none,
      CLLocation(latitude: 91, longitude: 0),
      CLLocation(
        coordinate: kCLLocationCoordinate2DInvalid,
        altitude: 0,
        horizontalAccuracy: 0,
        verticalAccuracy: 0,
        timestamp: .now
      ),
    ]
  )
  func dropsMissingOrInvalidLocation(location: CLLocation?) {
    #expect(PhotoLibraryClientImpl.coordinate(from: location) == nil)
  }

  @Test(
    "스크린샷 하위 유형이 있을 때만 스크린샷으로 본다",
    arguments: [
      (PHAssetMediaSubtype.photoScreenshot, true),
      (PHAssetMediaSubtype.photoScreenshot.union(.photoHDR), true),
      (PHAssetMediaSubtype.photoHDR, false),
      (PHAssetMediaSubtype(), false),
    ]
  )
  func detectsScreenshot(mediaSubtypes: PHAssetMediaSubtype, expected: Bool) {
    #expect(PhotoLibraryClientImpl.isScreenshot(mediaSubtypes) == expected)
  }
}
