import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 곧 만료 띠 칩 썸네일의 보관 규칙 (docs/ARCHITECTURE.md §4 카테고리 화면). 보관 집합은 대표 ∪ 띠 칩이고,
/// 띠 신호(`expiringChanged`)는 대표 신호(`coversChanged`)와 같은 규칙으로 읽고 놓는다.
@MainActor
struct LibraryCoverModelExpiringTests {
  @Test("띠 칩 식별자가 오면 카드 이벤트 없이 칩 썸네일을 읽는다")
  func chipsAreLoadedWithoutCardEvents() async {
    let photoLibrary = coverLibrary(["a", "b"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)

    model.expiringChanged(["a", "b"])
    await waitUntil { ["a", "b"].allSatisfy { model.thumbnails[$0]?.image != nil } }

    await cancelAndWait(loader)
  }

  @Test("대표와 띠 둘 다에 있는 사진은 한 번 읽고, 한쪽에서 빠져도 남고 둘 다에서 빠지면 놓는다")
  func sharedPhotoIsKeptUntilBothRelease() async {
    let photoLibrary = coverLibrary(["a"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.gifticon: ["a"]])
    model.expiringChanged(["a"])
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await settle()
    #expect(photoLibrary.requestCount("a") == 1)

    model.coversChanged([:])
    #expect(model.thumbnails["a"]?.image != nil)

    model.coversChanged([.gifticon: ["a"]])
    model.expiringChanged([])
    #expect(model.thumbnails["a"]?.image != nil)

    model.coversChanged([:])
    #expect(model.thumbnails["a"] == nil)
    // 둘 다에서 빠지기 전에는 다시 읽지 않았다.
    #expect(photoLibrary.requestCount("a") == 1)
    await cancelAndWait(loader)
  }

  @Test("띠가 비면 칩 썸네일을 놓고 대표는 그대로 둔다")
  func emptyStripReleasesChipsOnly() async {
    let photoLibrary = coverLibrary(["cover", "chip"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["cover"]])
    model.expiringChanged(["chip"])
    await waitUntil { model.thumbnails["cover"]?.image != nil && model.thumbnails["chip"]?.image != nil }

    model.expiringChanged([])

    #expect(model.thumbnails["chip"] == nil)
    #expect(model.thumbnails["cover"]?.image != nil)
    await cancelAndWait(loader)
  }

  @Test("로더보다 띠 칩이 먼저 오면 로더가 시작될 때 읽는다")
  func chipsBeforeLoaderAreLoadedOnStart() async {
    let photoLibrary = coverLibrary(["a"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)

    model.expiringChanged(["a"])
    await settle()
    #expect(photoLibrary.requestCount("a") == 0)

    let loader = await startLoader(model)
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(loader)
  }

  @Test("대체 상태 칩은 띠 신호로 다시 읽지 않고 칩이 다시 보이면 다시 읽는다")
  func unavailableChipIsRetriedOnlyWhenAppearing() async {
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["x": .failure(.notAvailableLocally), "b": .success(.stub())]
    )
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.expiringChanged(["x"])
    await waitUntil { model.thumbnails["x"]?.unavailableReason == .inCloudOnly }

    // 진행률마다 오는 띠 신호가 iCloud 에만 있는 사진을 다시 요청하지 않는다.
    model.expiringChanged(["x", "b"])
    await waitUntil { model.thumbnails["b"]?.image != nil }
    #expect(photoLibrary.requestCount("x") == 1)

    model.cardAppeared(ids: ["x"])
    await waitUntil { photoLibrary.requestCount("x") == 2 }
    await cancelAndWait(loader)
  }
}
