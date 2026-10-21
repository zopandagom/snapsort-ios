import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 격자가 아닌 화면(기프티콘 목록)이 썸네일 칸을 빌리는 `thumbnailScreenAppeared(category:)`.
@MainActor
struct CategoryModelThumbnailScreenTests {
  @Test("다른 카테고리를 보고 있었으면 썸네일과 내용을 비우고 저장소는 읽지 않는다")
  func switchingCategoryClearsWithoutReading() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let cell = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(cell)
    await cancelAndWait(appear)
    let readCount = photoLibrary.loadImageRequests.count

    let screen = Task { await model.thumbnailScreenAppeared(category: .gifticon) }
    await waitUntil { model.category == .gifticon }

    #expect(model.thumbnails.isEmpty)
    #expect(model.content == .loading)
    await settle()
    #expect(photoLibrary.loadImageRequests.count == readCount)

    await cancelAndWait(screen)
  }

  @Test("같은 카테고리로 다시 열면 보관한 썸네일을 두고 다시 읽지 않는다")
  func sameCategoryKeepsRetainedThumbnails() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["g": .success(.stub())])
    let model = CategoryModel.fixture(photoLibrary: photoLibrary, photoStore: PhotoStoreClientFake())
    let first = Task { await model.thumbnailScreenAppeared(category: .gifticon) }
    await waitUntil { model.category == .gifticon }
    let cell = Task { await model.thumbnailAppeared(id: "g", in: .gifticon) }
    await waitUntil { model.thumbnails["g"]?.image != nil }
    // 상세를 열면 목록 화면과 칸의 Task 가 끝난다.
    await cancelAndWait(cell)
    await cancelAndWait(first)

    let second = Task { await model.thumbnailScreenAppeared(category: .gifticon) }
    await settle()
    #expect(model.thumbnails["g"]?.image != nil)
    let again = Task { await model.thumbnailAppeared(id: "g", in: .gifticon) }
    await settle()
    #expect(photoLibrary.loadImageRequests == [LoadImageRequest(id: "g", size: .thumbnail)])

    await cancelAndWait(again)
    await cancelAndWait(second)
  }

  @Test("넘겨받은 뒤에는 그 카테고리 칸의 썸네일을 읽는다")
  func thumbnailsLoadAfterScreenAppeared() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["g": .success(.stub())])
    let model = CategoryModel.fixture(photoLibrary: photoLibrary, photoStore: PhotoStoreClientFake())

    // 넘겨받기 전의 칸은 지난 카테고리 칸으로 보고 읽지 않는다.
    await model.thumbnailAppeared(id: "g", in: .gifticon)
    #expect(photoLibrary.loadImageRequests.isEmpty)

    let screen = Task { await model.thumbnailScreenAppeared(category: .gifticon) }
    await waitUntil { model.category == .gifticon }
    let cell = Task { await model.thumbnailAppeared(id: "g", in: .gifticon) }
    await waitUntil { model.thumbnails["g"]?.image != nil }

    await cancelAndWait(cell)
    await cancelAndWait(screen)
  }

  @Test("넘겨받은 뒤 지난 격자 Task 의 늦은 결과는 내용을 바꾸지 않는다")
  func lateGridResultAfterScreenAppearedIsDropped() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [.dated(id: "a", nil)],
      onAssets: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let grid = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(0) }
    grid.cancel()

    let screen = Task { await model.thumbnailScreenAppeared(category: .gifticon) }
    await waitUntil { model.category == .gifticon }
    gates.open(0)
    await grid.value

    #expect(model.content == .loading)

    await cancelAndWait(screen)
  }
}
