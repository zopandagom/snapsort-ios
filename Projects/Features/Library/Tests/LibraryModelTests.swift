import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

@MainActor
struct LibraryModelTests {
  @Test("화면 진입 시 스크린샷 수를 불러온다", arguments: [0, 3])
  func onAppearLoadsCount(count: Int) async {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .authorized,
        screenshotIdentifiers: (0 ..< count).map { "screenshot-\($0)" }
      )
    )

    await model.onAppear()

    #expect(model.screenshotCount == count)
  }
}
