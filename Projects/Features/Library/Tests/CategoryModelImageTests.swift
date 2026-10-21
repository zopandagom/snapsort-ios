import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 썸네일과 상세. appeared 이벤트는 칸·상세가 보이는 동안(Task 가 취소될 때까지) 돌아오지 않으므로,
/// Task 로 부르고 상태를 확인한 뒤 취소하고 끝나기를 기다린다.
@MainActor
struct CategoryModelImageTests {
  @Test("칸이 보이면 썸네일 크기로 읽어 보이고, 보이는 동안 상태가 남는다")
  func thumbnailLoadsThumbnailSize() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)

    let cell = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }
    #expect(photoLibrary.loadImageRequests == [LoadImageRequest(id: "a", size: .thumbnail)])
    await settle()
    #expect(model.thumbnails["a"]?.image != nil)

    await cancelAndWait(cell)
    await cancelAndWait(appear)
  }

  @Test(
    "읽지 못하면 이유별 대체 상태다",
    arguments: [
      (ImageLoadError?.some(.notAvailableLocally), ImageUnavailableReason.inCloudOnly),
      (nil, .notFound),
      (.failed, .failed),
    ]
  )
  func thumbnailUnavailableReasons(error: ImageLoadError?, reason: ImageUnavailableReason) async {
    // 결과가 없는 식별자는 보관함에 없는 것이다.
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: error.map { ["a": .failure($0)] } ?? [:])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)

    let cell = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.unavailableReason == reason }

    await cancelAndWait(cell)
    await cancelAndWait(appear)
  }

  @Test("iCloud 대체 버전도 이미지로 보인다")
  func thumbnailFallbackIsShown() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub(isLocalFallback: true))])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)

    let cell = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }
    #expect(model.thumbnails["a"]?.image?.isLocalFallback == true)

    await cancelAndWait(cell)
    await cancelAndWait(appear)
  }

  @Test("읽는 중에 칸이 사라지면 읽기를 취소하고 상태를 지운다")
  func thumbnailCancelClearsState() async {
    // 읽기는 취소될 때까지 끝나지 않는다. 읽은 뒤에 사라지는 경우는 `coveredThumbnailsAreKept` 가 본다.
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["a": .success(.stub())],
      loadGate: { _ in try? await Task.sleep(for: .seconds(3600)) }
    )
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let cell = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.isLoading == true && photoLibrary.loadImageRequests.count == 1 }

    await cancelAndWait(cell)

    #expect(model.thumbnails["a"] == nil)
    await cancelAndWait(appear)
  }

  @Test("사라졌다 다시 보인 칸은 지난 읽기의 늦은 결과로 지워지지 않는다")
  func reappearedThumbnailIgnoresLateResult() async {
    // 첫 읽기만 붙잡는다. 취소돼도 열 때까지 기다려, 다시 보인 칸이 읽은 뒤에 지난 읽기가 끝나게 한다.
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let counter = CallCounter()
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["a": .success(.stub())],
      loadGate: { _ in await gates.pass(counter.next()) }
    )
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)

    let first = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { gates.hasEntered(0) }
    first.cancel()
    let second = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }

    gates.open(0)
    await first.value
    #expect(model.thumbnails["a"]?.image != nil)

    await cancelAndWait(second)
    await cancelAndWait(appear)
  }

  @Test("이미 읽은 칸이 다시 불리면 다시 읽지 않는다")
  func loadedThumbnailIsNotReloaded() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let first = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }

    let second = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await settle()

    #expect(photoLibrary.loadImageRequests.count == 1)
    #expect(model.thumbnails["a"]?.image != nil)

    await cancelAndWait(first)
    await cancelAndWait(second)
    await cancelAndWait(appear)
  }

  @Test("지난 칸의 Task 가 늦게 취소돼도 지금 칸의 상태를 지우지 않는다")
  func staleThumbnailCancelKeepsCurrent() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let first = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }
    let second = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await settle()

    await cancelAndWait(first)
    #expect(model.thumbnails["a"]?.image != nil)

    // 지금 칸이 사라지면 보관 목록에 남는다.
    await cancelAndWait(second)
    #expect(model.thumbnails["a"]?.image != nil)
    await cancelAndWait(appear)
  }

  @Test("지난 카테고리 칸이 늦게 보여도 지금 카테고리 상태를 바꾸지 않는다")
  func thumbnailFromPreviousCategoryIsIgnored() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)

    // 지난 카테고리 칸이면 기다리지 않고 바로 돌아온다.
    await model.thumbnailAppeared(id: "a", in: .food)

    #expect(photoLibrary.loadImageRequests.isEmpty)
    #expect(model.thumbnails.isEmpty)
    await cancelAndWait(appear)
  }

  @Test("다른 카테고리를 열면 남겨 둔 것까지 썸네일을 비운다")
  func switchingCategoryClearsThumbnails() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub()), "b": .success(.stub())])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    // a 는 사라져 보관 목록에 있고, b 는 아직 보이는 채로 다른 카테고리를 연다.
    let retained = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    let visible = Task { await model.thumbnailAppeared(id: "b", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil && model.thumbnails["b"]?.image != nil }
    await cancelAndWait(retained)
    await cancelAndWait(appear)

    let food = Task { await model.onAppear(category: .food) }
    await waitUntil { model.category == .food }
    #expect(model.thumbnails.isEmpty)

    // 지난 칸이 늦게 사라져도 아무것도 하지 않는다.
    await cancelAndWait(visible)
    #expect(model.thumbnails.isEmpty)
    await cancelAndWait(food)

    // 원래 카테고리로 돌아와 다시 보이면 다시 읽는다.
    let people = Task { await model.onAppear(category: .people) }
    await waitUntil { model.category == .people }
    let again = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }
    #expect(photoLibrary.loadImageRequests.count(where: { $0.id == "a" }) == 2)
    await cancelAndWait(again)
    await cancelAndWait(people)
  }

  @Test("상세는 기기에 있는 가장 큰 버전으로 읽고, 읽는 동안 불러오는 중이다")
  func detailLoadsLargestAvailable() async {
    let gates = CallGates(holding: [0])
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["a": .success(.stub())],
      loadGate: { _ in await gates.pass(0) }
    )
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)

    let detail = Task { await model.detailAppeared(id: "a") }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.detail?.id == "a")
    #expect(model.detail?.state.isLoading == true)

    gates.open(0)
    await waitUntil { model.detail?.state.image != nil }
    #expect(model.detail?.id == "a")
    #expect(photoLibrary.loadImageRequests == [LoadImageRequest(id: "a", size: .largestAvailable)])

    await cancelAndWait(detail)
  }

  @Test(
    "상세를 읽지 못하면 이유별 상태다",
    arguments: [
      (ImageLoadError?.some(.notAvailableLocally), ImageUnavailableReason.inCloudOnly),
      (nil, .notFound),
      (.failed, .failed),
    ]
  )
  func detailUnavailableReasons(error: ImageLoadError?, reason: ImageUnavailableReason) async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: error.map { ["a": .failure($0)] } ?? [:])
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)

    let detail = Task { await model.detailAppeared(id: "a") }
    await waitUntil { model.detail?.state.unavailableReason == reason }
    #expect(model.detail?.id == "a")

    await cancelAndWait(detail)
  }

  @Test("상세가 닫혀 Task 가 취소되면 이미지를 놓고, 읽는 중이면 늦은 결과를 버린다")
  func detailCancelReleasesImage() async {
    // 읽은 뒤에 닫는다.
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let loaded = Task { await model.detailAppeared(id: "a") }
    await waitUntil { model.detail?.state.image != nil }
    await cancelAndWait(loaded)
    #expect(model.detail == nil)

    // 읽는 중에 닫는다. 취소돼도 읽기가 열 때까지 기다리다 늦게 끝난다.
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let slowLibrary = PhotoLibraryClientFake(
      loadImageResults: ["a": .success(.stub())],
      loadGate: { _ in await gates.pass(0) }
    )
    let slowModel = CategoryModel(photoLibrary: slowLibrary, photoStore: nil)
    let loading = Task { await slowModel.detailAppeared(id: "a") }
    await waitUntil { gates.hasEntered(0) }
    loading.cancel()
    gates.open(0)
    await loading.value
    #expect(slowModel.detail == nil)
  }

  @Test("다른 사진 상세를 열면 지난 읽기 결과로 덮지 않는다")
  func detailOfOtherPhotoIgnoresLateResult() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["a": .success(.stub()), "b": .success(.stub())],
      loadGate: { _ in await gates.pass(counter.next()) }
    )
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let first = Task { await model.detailAppeared(id: "a") }
    await waitUntil { gates.hasEntered(0) }
    let second = Task { await model.detailAppeared(id: "b") }
    await waitUntil { model.detail?.id == "b" && model.detail?.state.image != nil }

    // 지난 읽기가 성공으로 늦게 끝나도 지금 상세를 덮지 않고 돌아온다.
    gates.open(0)
    await first.value
    #expect(model.detail?.id == "b")
    #expect(model.detail?.state.image != nil)

    await cancelAndWait(second)
  }

  @Test("지난 상세 Task 가 늦게 취소돼도 지금 상세를 지우지 않는다")
  func staleDetailCancelKeepsCurrent() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let first = Task { await model.detailAppeared(id: "a") }
    await waitUntil { model.detail?.state.image != nil }
    let second = Task { await model.detailAppeared(id: "a") }
    // 두 번째가 불러오는 중으로 바꾼 뒤 요청하므로, 요청이 둘이고 이미지가 있으면 두 번째가 읽은 것이다.
    await waitUntil { photoLibrary.loadImageRequests.count == 2 && model.detail?.state.image != nil }

    await cancelAndWait(first)
    #expect(model.detail?.state.image != nil)

    await cancelAndWait(second)
    #expect(model.detail == nil)
  }
}

/// 썸네일은 연 카테고리의 칸만 읽으므로, 인물 카테고리를 열어 둔다.
@MainActor
func openPeople(photoLibrary: PhotoLibraryClientFake) async -> (CategoryModel, Task<Void, Never>) {
  let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil, categories: [.people, .food])])
  let model = CategoryModel.fixture(photoLibrary: photoLibrary, photoStore: photoStore)
  let appear = Task { await model.onAppear(category: .people) }
  await waitUntil { model.content != .loading }
  return (model, appear)
}

/// 칸의 Task 가 끝난 뒤에도 읽은 썸네일을 최근 `CategoryModel.retainedThumbnailLimit` 장까지 남기는 보관 목록.
@MainActor
struct CategoryModelThumbnailRetentionTests {
  @Test("상세를 열어 칸의 Task 가 모두 취소돼도 읽은 썸네일을 놓지 않고, 다시 보이면 다시 읽지 않는다")
  func coveredThumbnailsAreKept() async {
    let ids = ["a", "b", "c"]
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { (
      $0,
      .success(.stub())
    ) }))
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let cells = ids.map { id in Task { await model.thumbnailAppeared(id: id, in: .people) } }
    await waitUntil { ids.allSatisfy { model.thumbnails[$0]?.image != nil } }

    // 상세가 아래 격자를 덮어 보이던 칸의 Task 가 모두 취소된다.
    for cell in cells {
      await cancelAndWait(cell)
    }
    #expect(ids.allSatisfy { model.thumbnails[$0]?.image != nil })

    // 돌아와 다시 보인다.
    let shownAgain = ids.map { id in Task { await model.thumbnailAppeared(id: id, in: .people) } }
    await settle()
    #expect(photoLibrary.loadImageRequests.count == 3)
    #expect(ids.allSatisfy { model.thumbnails[$0]?.image != nil })

    for cell in shownAgain {
      await cancelAndWait(cell)
    }
    await cancelAndWait(appear)
  }

  @Test("사라진 칸의 썸네일은 최근 64장까지만 두고 오래된 것부터 놓는다")
  func retainedThumbnailsAreBounded() async {
    let limit = CategoryModel.retainedThumbnailLimit
    let ids = (0 ... limit).map { "image-\($0)" }
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { (
      $0,
      .success(.stub())
    ) }))
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)

    // 한 칸씩 보였다 사라진다(스크롤).
    for id in ids {
      let cell = Task { await model.thumbnailAppeared(id: id, in: .people) }
      await waitUntil { model.thumbnails[id]?.image != nil }
      await cancelAndWait(cell)
    }

    #expect(model.thumbnails[ids[0]] == nil)
    #expect(ids.dropFirst().allSatisfy { model.thumbnails[$0]?.image != nil })
    #expect(model.thumbnails.count == limit)
    await cancelAndWait(appear)
  }

  @Test("읽지 못한 칸은 사라지면 지워, 다시 보이면 다시 읽는다")
  func unavailableThumbnailIsNotRetained() async {
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: ["a": .failure(.failed)])
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let cell = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.unavailableReason == .failed }

    await cancelAndWait(cell)
    #expect(model.thumbnails["a"] == nil)

    let shownAgain = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.unavailableReason == .failed }
    #expect(photoLibrary.loadImageRequests.count == 2)
    await cancelAndWait(shownAgain)
    await cancelAndWait(appear)
  }
}
