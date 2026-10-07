import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

@MainActor
struct LibraryModelTests {
  @Test("권한이 있으면 화면 진입 시 스크린샷 수를 불러온다")
  func onAppearWithAccessLoadsCount() async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .limited, screenshotIdentifiers: ["a", "b", "c"])
    )

    await model.onAppear()

    #expect(model.access == .limited)
    #expect(model.screenshotCount == 3)
  }

  @Test("권한이 없으면 스크린샷을 조회하지 않는다")
  func onAppearWithoutAccessSkipsFetch() async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .denied, screenshotIdentifiers: ["a"])
    )

    await model.onAppear()

    #expect(model.access == .denied)
    #expect(model.screenshotCount == 0)
  }

  @Test("권한을 아직 묻지 않았으면 화면 진입 시 권한을 요청하지 않고 스크린샷도 조회하지 않는다")
  func onAppearWhenNotDeterminedDoesNotRequestAccess() async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .notDetermined,
        stateAfterRequest: .authorized,
        screenshotIdentifiers: ["a"]
      )
    )

    await model.onAppear()

    #expect(model.access == .notDetermined)
    #expect(model.screenshotCount == 0)
  }

  @Test(
    "시작 버튼을 누르면 권한 요청 결과를 반영하고, 읽을 수 있을 때만 스크린샷을 불러온다",
    arguments: [
      (PhotoAccessState.authorized, 2),
      (.limited, 2),
      (.denied, 0),
    ]
  )
  func startButtonTappedRequestsAccess(result: PhotoAccessState, expectedCount: Int) async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .notDetermined,
        stateAfterRequest: result,
        screenshotIdentifiers: ["a", "b"]
      )
    )

    await model.startButtonTapped()

    #expect(model.access == result)
    #expect(model.screenshotCount == expectedCount)
  }
}
