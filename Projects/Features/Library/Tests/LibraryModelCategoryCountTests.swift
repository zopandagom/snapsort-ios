import Core
import Foundation
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

@MainActor
struct LibraryModelCategoryCountTests {
  @Test("화면 진입 시 저장된 카테고리 개수와 여행 수를 불러온다")
  func onAppearLoadsCategoryCounts() async {
    let photoStore = PhotoStoreClientFake(
      images: [
        .stub(id: "a", categories: [.gifticon]),
        .stub(id: "b", categories: [.gifticon, .shopping]),
        .stub(id: "c", categories: [.food]),
      ],
      trips: [.stub(), .stub()]
    )
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(photoLibrary: photoLibrary, indexing: nil, photoStore: photoStore, notification: nil)
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(model.categoryCounts == [.gifticon: 2, .shopping: 1, .food: 1, .travel: 2])
  }

  @Test("여행이 없으면 여행 개수를 넣지 않는다")
  func noTripsOmitsTravel() async {
    let photoStore = PhotoStoreClientFake(images: [.stub(id: "a", categories: [.document])])
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(photoLibrary: photoLibrary, indexing: nil, photoStore: photoStore, notification: nil)
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(model.categoryCounts == [.document: 1])
  }

  @Test("저장소를 읽지 못하면 개수를 비워 둔다")
  func storeFailureLeavesCountsEmpty() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: nil,
      photoStore: PhotoStoreClientFake(images: [.stub(id: "a", categories: [.food])], error: .failed),
      notification: nil
    )
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(model.categoryCounts.isEmpty)
  }

  @Test("진행률을 받을 때마다 저장소에서 개수를 다시 읽는다")
  func progressRefreshesCategoryCounts() async {
    let photoStore = PhotoStoreClientFake()
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(photoLibrary: photoLibrary, indexing: indexing, photoStore: photoStore, notification: nil)
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }

    // 인덱서가 한 배치를 저장하고 진행률을 보낸 것처럼 흉내 낸다.
    try? await photoStore.save([.stub(id: "a", categories: [.receipt])])
    try? await photoStore.replaceTrips([.stub()])
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 0))
    await waitUntil { model.categoryCounts == [.receipt: 1, .travel: 1] }

    appear.cancel()
    await appear.value
  }

  @Test("진행률을 받을 때마다(같은 값 포함) 저장소 변경 번호가 오른다")
  func progressBumpsStoreRevision() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    let before = model.storeRevision

    // 소급이 끝날 때처럼 같은 값의 진행률이 다시 와도 오른다.
    let progress = IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 0)
    indexing.sendProgress(progress)
    await waitUntil { model.storeRevision == before + 1 }
    indexing.sendProgress(progress)
    await waitUntil { model.storeRevision == before + 2 }

    appear.cancel()
    await appear.value
  }

  @Test("인덱싱이 멈추면 저장소 변경 번호가 오른다")
  func stopBumpsStoreRevision() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    let before = model.storeRevision

    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }
    #expect(model.storeRevision == before + 1)

    appear.cancel()
    await appear.value
  }

  @Test("화면을 떠나 구독을 끝내면 번호를 올리지 않는다")
  func cancelDoesNotBumpStoreRevision() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    let before = model.storeRevision

    appear.cancel()
    await appear.value

    #expect(model.storeRevision == before)
    #expect(!model.isIndexingStopped)
  }
}
