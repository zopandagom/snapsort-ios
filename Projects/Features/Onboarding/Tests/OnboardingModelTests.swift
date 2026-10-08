import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import OnboardingFeature

@MainActor
struct OnboardingModelTests {
  @Test(
    "생성 시점에 현재 권한 상태를 읽어 둔다",
    arguments: [PhotoAccessState.authorized, .limited, .denied, .notDetermined]
  )
  func initReadsCurrentAccess(state: PhotoAccessState) {
    let model = OnboardingModel(photoLibrary: PhotoLibraryClientFake(currentState: state))

    #expect(model.access == state)
  }

  @Test(
    "시작 버튼을 누르면 권한 요청 결과를 반영한다",
    arguments: [PhotoAccessState.authorized, .limited, .denied]
  )
  func startButtonTappedRequestsAccess(result: PhotoAccessState) async {
    let model = OnboardingModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: result)
    )

    await model.startButtonTapped()

    #expect(model.access == result)
  }
}
