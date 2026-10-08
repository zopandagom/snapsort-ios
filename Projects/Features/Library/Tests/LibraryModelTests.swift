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
}
