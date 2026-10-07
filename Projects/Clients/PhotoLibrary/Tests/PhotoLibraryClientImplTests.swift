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
}
