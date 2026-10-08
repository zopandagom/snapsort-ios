import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

@MainActor
struct LibraryModelTests {
  @Test("화면 진입 시 이미지 수를 불러온다", arguments: [0, 3])
  func onAppearLoadsCount(count: Int) async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .authorized,
        imageIdentifiers: (0 ..< count).map { "image-\($0)" }
      )
    )

    await model.onAppear()

    #expect(model.imageCount == count)
  }

  @Test(
    "제한 접근일 때만 isLimited 가 참이다",
    arguments: [
      (PhotoAccessState.limited, true),
      (.authorized, false),
      (.notDetermined, false),
      (.denied, false),
    ]
  )
  func isLimitedReflectsAccessState(state: PhotoAccessState, expected: Bool) {
    let model = LibraryModel(photoLibrary: PhotoLibraryClientFake(currentState: state))

    #expect(model.isLimited == expected)
  }

  @Test("온보딩 전에 만들어져도 화면 진입 시 제한 접근 상태를 다시 읽는다")
  func onAppearRereadsLimitedAccess() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .limited)
    let model = LibraryModel(photoLibrary: photoLibrary)
    _ = await photoLibrary.requestAccess()

    await model.onAppear()

    #expect(model.isLimited)
  }

  @Test("사진 더 선택을 누르면 선택 화면을 띄우고 닫힌 뒤 이미지 수를 다시 불러온다")
  func selectMorePhotosReloadsCount() async {
    let photoLibrary = PhotoLibraryClientFake(
      currentState: .limited,
      imageIdentifiers: ["image-0"],
      imageIdentifiersAfterPicker: ["image-0", "image-1", "image-2"]
    )
    let model = LibraryModel(photoLibrary: photoLibrary)
    await model.onAppear()

    await model.selectMorePhotosTapped()

    #expect(photoLibrary.limitedPickerPresentCount == 1)
    #expect(model.imageCount == 3)
  }
}
