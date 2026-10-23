import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 같은 이미지를 읽는 여러 칸의 썸네일 주인 규칙. 한 칸이 사라져도 다른 칸이 필요한 읽기는 취소하지 않고,
/// 마지막 칸이 사라질 때만 보관 목록에 한 번 든다.
@MainActor
struct CategoryModelSharedThumbnailTests {
  @Test("같은 이미지의 두 칸 중 한 칸이 읽는 중 사라져도 다른 칸이 썸네일을 받는다")
  func otherCellReceivesThumbnailWhenOneVanishesWhileLoading() async {
    // 첫 읽기만 붙잡고, 취소돼도 열 때까지 기다리게 해 두 칸이 함께 읽는 중이게 한다.
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
    let second = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { model.thumbnails["a"]?.image != nil }

    // 먼저 읽던 칸이 사라진다. 다른 칸이 보이는 동안 상태를 지우지 않는다.
    first.cancel()
    gates.open(0)
    await first.value
    #expect(model.thumbnails["a"]?.image != nil)

    await cancelAndWait(second)
    await cancelAndWait(appear)
  }

  @Test("두 칸이 읽는 중일 때 한 칸만 사라지면 남은 칸의 읽기가 이어 쓴다")
  func remainingCellKeepsLoadingWhenOtherVanishes() async {
    let gates = CallGates(holding: [0, 1])
    let counter = CallCounter()
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["a": .success(.stub())],
      loadGate: { _ in await gates.pass(counter.next()) }
    )
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let first = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { gates.hasEntered(0) }
    let second = Task { await model.thumbnailAppeared(id: "a", in: .people) }
    await waitUntil { gates.hasEntered(1) }

    await cancelAndWait(first)
    #expect(model.thumbnails["a"]?.isLoading == true)

    gates.open(1)
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(second)
    await cancelAndWait(appear)
  }

  @Test("같은 이미지의 한 칸이 읽은 뒤 사라져도 다른 칸이 보이는 동안은 보관 목록에 들지 않는다")
  func sharedThumbnailIsNotRetainedWhileOtherCellIsVisible() async {
    let limit = CategoryModel.retainedThumbnailLimit
    let others = (0 ... limit).map { "other-\($0)" }
    let ids = ["shared"] + others
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { (
      $0,
      .success(.stub())
    ) }))
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let first = Task { await model.thumbnailAppeared(id: "shared", in: .people) }
    await waitUntil { model.thumbnails["shared"]?.image != nil }
    let second = Task { await model.thumbnailAppeared(id: "shared", in: .people) }
    await settle()
    await cancelAndWait(first)

    // 다른 칸이 64장 넘게 보였다 사라져도 보이는 칸의 썸네일은 지워지지 않는다.
    for id in others {
      let cell = Task { await model.thumbnailAppeared(id: id, in: .people) }
      await waitUntil { model.thumbnails[id]?.image != nil }
      await cancelAndWait(cell)
    }
    #expect(model.thumbnails["shared"]?.image != nil)

    await cancelAndWait(second)
    await cancelAndWait(appear)
  }

  @Test("두 칸이 모두 사라지면 보관 목록에 한 번만 든다")
  func sharedThumbnailIsRetainedOnceAfterBothVanish() async {
    let limit = CategoryModel.retainedThumbnailLimit
    let others = (0 ..< limit - 1).map { "other-\($0)" }
    let ids = ["shared"] + others
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { (
      $0,
      .success(.stub())
    ) }))
    let (model, appear) = await openPeople(photoLibrary: photoLibrary)
    let first = Task { await model.thumbnailAppeared(id: "shared", in: .people) }
    await waitUntil { model.thumbnails["shared"]?.image != nil }
    let second = Task { await model.thumbnailAppeared(id: "shared", in: .people) }
    await settle()
    await cancelAndWait(first)
    await cancelAndWait(second)

    // 한도(64)에서 shared 가 한 자리만 차지하면 나머지 63장과 함께 모두 남는다. 두 번 들었다면 한 장이 밀려 나간다.
    for id in others {
      let cell = Task { await model.thumbnailAppeared(id: id, in: .people) }
      await waitUntil { model.thumbnails[id]?.image != nil }
      await cancelAndWait(cell)
    }
    #expect(model.thumbnails.count == limit)
    #expect(ids.allSatisfy { model.thumbnails[$0]?.image != nil })
    await cancelAndWait(appear)
  }

  @Test("두 칸이 함께 읽으면 어느 쪽이 먼저 끝나도 읽은 썸네일이고 두 칸 모두 읽는다")
  func concurrentReadsEndLoadedInEitherOrder() async {
    for firstFinishesFirst in [true, false] {
      let gates = CallGates(holding: [0, 1])
      let counter = CallCounter()
      let photoLibrary = PhotoLibraryClientFake(
        loadImageResults: ["a": .success(.stub())],
        loadGate: { _ in await gates.pass(counter.next()) }
      )
      let (model, appear) = await openPeople(photoLibrary: photoLibrary)
      let first = Task { await model.thumbnailAppeared(id: "a", in: .people) }
      await waitUntil { gates.hasEntered(0) }
      let second = Task { await model.thumbnailAppeared(id: "a", in: .people) }
      await waitUntil { gates.hasEntered(1) }
      #expect(photoLibrary.loadImageRequests.count == 2)

      gates.open(firstFinishesFirst ? 0 : 1)
      await waitUntil { model.thumbnails["a"]?.image != nil }
      gates.open(firstFinishesFirst ? 1 : 0)
      await settle()
      #expect(model.thumbnails["a"]?.image != nil)

      await cancelAndWait(first)
      await cancelAndWait(second)
      await cancelAndWait(appear)
    }
  }
}
