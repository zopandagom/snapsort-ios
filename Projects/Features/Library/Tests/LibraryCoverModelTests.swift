import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 보관함 카드 대표 썸네일의 읽기 규칙 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 로더(`onAppear()`)는 보관함 NavigationStack 의 `.task` 수명이고, 대표 신호(`coversChanged`)가 카드 이벤트 없이 읽기를 시작한다.
@MainActor
struct LibraryCoverModelTests {
  @Test("대표가 오면 카드 이벤트 없이 모든 대표 썸네일을 읽어 둔다")
  func coversAreLoadedWithoutCardEvents() async {
    let photoLibrary = coverLibrary(["a", "b", "c"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)

    model.coversChanged([.food: ["a", "b"], .people: ["c"]])
    await waitUntil { ["a", "b", "c"].allSatisfy { model.thumbnails[$0]?.image != nil } }

    await cancelAndWait(loader)
  }

  @Test("대표가 바뀌면 카드가 보이지 않아도 새로 든 대표를 읽는다")
  func changedCoversAreLoadedWithoutCards() async {
    // push 한 동안처럼 카드 이벤트 없이 대표 신호만 온다.
    let photoLibrary = coverLibrary(["a", "b"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)

    model.coversChanged([.food: ["a"]])
    await waitUntil { model.thumbnails["a"]?.image != nil }
    model.coversChanged([.food: ["b", "a"]])
    await waitUntil { model.thumbnails["b"]?.image != nil }

    await cancelAndWait(loader)
  }

  @Test("이미 읽은 썸네일은 대표가 다시 와도 다시 읽지 않는다")
  func loadedThumbnailIsNotReloaded() async {
    let photoLibrary = coverLibrary(["a", "b"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)

    model.coversChanged([.food: ["a"]])
    await waitUntil { model.thumbnails["a"]?.image != nil }
    model.coversChanged([.food: ["a"], .people: ["b"]])
    await waitUntil { model.thumbnails["b"]?.image != nil }

    #expect(photoLibrary.requestCount("a") == 1)
    await cancelAndWait(loader)
  }

  @Test("같은 이미지가 두 카테고리 대표에 있으면 한 번만 읽는다")
  func sharedCoverIsLoadedOnce() async {
    let photoLibrary = coverLibrary(["a"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)

    model.coversChanged([.gifticon: ["a"], .shopping: ["a"]])
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await settle()

    #expect(photoLibrary.requestCount("a") == 1)
    await cancelAndWait(loader)
  }

  @Test("로더보다 대표가 먼저 오면 로더가 시작될 때 읽는다")
  func coversBeforeLoaderAreLoadedOnStart() async {
    let photoLibrary = coverLibrary(["a"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)

    model.coversChanged([.food: ["a"]])
    await settle()
    #expect(photoLibrary.requestCount("a") == 0)

    let loader = await startLoader(model)
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(loader)
  }

  @Test("대표보다 로더가 먼저 시작되면 대표가 올 때 읽는다")
  func coversAfterLoaderAreLoadedOnSignal() async {
    let photoLibrary = coverLibrary(["a"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    #expect(photoLibrary.requestCount("a") == 0)

    model.coversChanged([.food: ["a"]])
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(loader)
  }

  @Test(
    "iCloud 에만 있음·없음·실패는 대체 상태로 두고 카드가 다시 보이면 다시 읽는다",
    arguments: [
      (ImageLoadError?.some(.notAvailableLocally), ImageUnavailableReason.inCloudOnly),
      (nil, .notFound),
      (.failed, .failed),
    ]
  )
  func unavailableCoverIsRetriedWhenCardAppears(error: ImageLoadError?, reason: ImageUnavailableReason) async {
    // 결과가 없는 식별자는 보관함에 없는 것이다.
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: error.map { ["x": .failure($0)] } ?? [:])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["x"]])
    await waitUntil { model.thumbnails["x"]?.unavailableReason == reason }

    model.cardAppeared(ids: ["x"])
    await waitUntil { photoLibrary.requestCount("x") == 2 }
    await settle()

    #expect(model.thumbnails["x"]?.unavailableReason == reason)
    await cancelAndWait(loader)
  }

  @Test("대체 상태는 대표가 다시 와도 다시 읽지 않는다")
  func unavailableCoverIsNotReloadedOnCoverSignal() async {
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["x": .failure(.notAvailableLocally), "b": .success(.stub())]
    )
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["x"]])
    await waitUntil { model.thumbnails["x"]?.unavailableReason == .inCloudOnly }

    // 진행률마다 오는 대표 신호가 iCloud 에만 있는 사진을 다시 요청하지 않는다.
    model.coversChanged([.food: ["x"], .people: ["b"]])
    await waitUntil { model.thumbnails["b"]?.image != nil }

    #expect(photoLibrary.requestCount("x") == 1)
    await cancelAndWait(loader)
  }

  @Test("다시 읽는 동안 대체 상태를 유지한다")
  func unavailableStateIsKeptWhileRetrying() async {
    let gates = LoadGates(holding: [LoadGates.Key("x", 1)])
    defer { gates.openAll() }
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["x": .failure(.notAvailableLocally)],
      loadGate: { id in await gates.pass(id) }
    )
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["x"]])
    await waitUntil { model.thumbnails["x"]?.unavailableReason == .inCloudOnly }

    model.cardAppeared(ids: ["x"])
    await waitUntil { gates.enteredCount("x") == 2 }

    #expect(model.thumbnails["x"]?.unavailableReason == .inCloudOnly)
    await cancelAndWait(loader)
  }

  @Test("읽은 칸과 읽는 중인 칸의 카드 이벤트는 요청을 더하지 않는다")
  func cardEventsForLoadedAndLoadingAddNoRequests() async {
    let gates = LoadGates(holding: [LoadGates.Key("b", 0)])
    defer { gates.openAll() }
    let photoLibrary = coverLibrary(["a", "b"], gates: gates)
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["a", "b"]])
    await waitUntil { model.thumbnails["a"]?.image != nil && gates.enteredCount("b") == 1 }

    model.cardAppeared(ids: ["a", "b"])
    await settle()

    #expect(photoLibrary.requestCount("a") == 1)
    #expect(photoLibrary.requestCount("b") == 1)
    await cancelAndWait(loader)
  }
}
