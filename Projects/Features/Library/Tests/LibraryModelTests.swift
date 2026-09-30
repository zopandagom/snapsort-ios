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

  @Test("시작 버튼을 누르면 권한 요청 결과를 반영하고 스크린샷을 불러온다")
  func startButtonTappedRequestsAccess() async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .notDetermined,
        stateAfterRequest: .authorized,
        screenshotIdentifiers: ["a", "b"]
      )
    )

    await model.startButtonTapped()

    #expect(model.access == .authorized)
    #expect(model.screenshotCount == 2)
  }
}
