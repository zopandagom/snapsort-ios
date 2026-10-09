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

  @Test("추가·삭제된 이미지를 그대로 알린다")
  func notifiesInsertedAndRemoved() {
    let inserted = [Self.asset(id: "new")]

    let change = ImageChangeObserver.imageChange(inserted: inserted, removed: ["old"])

    #expect(change == .incremental(inserted: inserted, removed: ["old"]))
  }

  @Test("추가·삭제가 없는 변경은 알리지 않는다")
  func ignoresChangeWithoutInsertOrRemove() {
    let change = ImageChangeObserver.imageChange(inserted: [], removed: [])

    #expect(change == nil)
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

  private static func asset(id: String) -> ImageAsset {
    ImageAsset(id: id, creationDate: nil, coordinate: nil, pixelWidth: 1, pixelHeight: 1, isScreenshot: false)
  }
}
