import Core
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 인덱싱 중·멈춤 상태와 다시 시도. 인덱싱은 멈춰도 다시 시도를 기다리므로, 결과를 확인한 뒤 Task 를 취소해 끝낸다.
@MainActor
struct LibraryModelIndexingStateTests {
  @Test("첫 진행률을 받기 전에도 인덱싱 중으로 보고, 다 분석하면 인덱싱 중이 아니다")
  func isIndexingUntilFinished() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 && model.isIndexing }
    #expect(model.indexingProgress == nil)

    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 0))
    await waitUntil { model.indexingProgress?.indexedCount == 1 }
    #expect(model.isIndexing)
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
    await waitUntil { model.indexingProgress?.isFinished == true }
    #expect(!model.isIndexing)

    appear.cancel()
    await appear.value
  }

  @Test("분류를 마친 뒤 글자를 읽는 동안(2단계)에도 인덱싱 중이고, 대기가 없어지면 인덱싱 중이 아니다")
  func isIndexingDuringTextPass() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 && model.isIndexing }

    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, pendingTextCount: 1))
    await waitUntil { model.indexingProgress?.pendingTextCount == 1 }
    #expect(model.isIndexing)
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 1))
    await waitUntil { model.indexingProgress?.recognizedTextCount == 1 }
    #expect(!model.isIndexing)

    appear.cancel()
    await appear.value
  }

  @Test("글자를 읽는 도중 스트림이 끝나면 멈춘 것으로 보고 마지막 진행률을 남긴다")
  func stopsDuringTextPass() async {
    let last = IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, pendingTextCount: 1)
    let indexing = IndexingClientFake(progress: [last])
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }

    await waitUntil { model.isIndexingStopped }
    #expect(!model.isIndexing)
    #expect(model.indexingProgress == last)
    #expect(model.indexingProgress?.phase == .recognizingText)

    appear.cancel()
    await appear.value
  }

  @Test("멈추거나 화면이 사라지면 인덱싱 중이 아니다")
  func isIndexingFalseAfterStopOrCancel() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    // 인덱싱 중 표시는 `run()` 전에 켜지므로, 스트림이 생긴 뒤에 끝내야 멈춤이 된다.
    await waitUntil { indexing.activeRunCount == 1 && model.isIndexing }

    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }
    #expect(!model.isIndexing)
    model.retryIndexingTapped()
    #expect(model.isIndexing)
    await waitUntil { indexing.runCount == 2 && model.isIndexing }
    appear.cancel()
    await appear.value

    #expect(!model.isIndexing)
  }

  @Test("화면을 나가자마자 다시 들어와도 지난 Task 가 새 인덱싱의 상태와 다시 시도를 덮지 않는다")
  func overlappingReappearKeepsNewState() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let firstAppear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }

    // 지난 Task 가 끝나기를 기다리지 않고 바로 다시 들어온다.
    firstAppear.cancel()
    let secondAppear = Task { await model.onAppear() }
    await firstAppear.value
    await waitUntil { indexing.runCount == 2 && indexing.activeRunCount == 1 }
    #expect(model.isIndexing)

    // 다시 시도 신호도 새 Task 에 닿아야 한다.
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }
    model.retryIndexingTapped()
    await waitUntil { indexing.runCount == 3 && indexing.activeRunCount == 1 }

    secondAppear.cancel()
    await secondAppear.value
  }

  @Test("멈춘 뒤 화면을 나갔다 다시 들어오면 멈춤을 풀고 인덱싱을 다시 시작한다")
  func reappearRestartsStoppedIndexing() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let firstAppear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }
    firstAppear.cancel()
    await firstAppear.value

    let secondAppear = Task { await model.onAppear() }
    await waitUntil { indexing.runCount == 2 && indexing.activeRunCount == 1 }
    #expect(!model.isIndexingStopped)

    secondAppear.cancel()
    await secondAppear.value
  }

  @Test("인덱싱 스트림이 중간에 끝나면 멈춘 것으로 보고 마지막 진행률을 남긴다")
  func streamEndMarksIndexingStopped() async {
    let last = IndexingProgress(totalCount: 10, indexedCount: 3, skippedCount: 0)
    let indexing = IndexingClientFake(progress: [last])
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }

    await waitUntil { model.isIndexingStopped }
    #expect(model.indexingProgress == last)

    appear.cancel()
    await appear.value
  }

  @Test("진행률을 하나도 보내지 못하고 끝나도 멈춘 것으로 보고, 다시 시도하면 다시 시작한다")
  func streamEndWithoutProgressMarksIndexingStopped() async {
    let indexing = IndexingClientFake(progress: [])
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { model.isIndexingStopped }
    #expect(model.indexingProgress == nil)

    model.retryIndexingTapped()

    await waitUntil { indexing.runCount == 2 }
    appear.cancel()
    await appear.value
  }

  @Test("멈출 때 저장소에서 개수를 한 번 더 읽는다")
  func stopRefreshesCategoryCounts() async {
    let photoStore = PhotoStoreClientFake()
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(photoLibrary: photoLibrary, indexing: indexing, photoStore: photoStore, notification: nil)
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }

    // 진행률을 보내기 전에 저장소를 바꾸고 멈춘 것처럼 흉내 낸다.
    try? await photoStore.save([.stub(id: "a", categories: [.map])])
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }

    #expect(model.categoryCounts == [.map: 1])
    appear.cancel()
    await appear.value
  }

  @Test("멈춘 인덱싱에서 다시 시도를 누르면 인덱싱을 다시 시작한다")
  func retryRestartsStoppedIndexing() async {
    let indexing = IndexingClientFake(
      progress: [IndexingProgress(totalCount: 10, indexedCount: 3, skippedCount: 0)],
      finishesAfterProgress: false
    )
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: PhotoStoreClientFake(),
      notification: nil
    )
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }

    model.retryIndexingTapped()

    await waitUntil { indexing.runCount == 2 && indexing.activeRunCount == 1 && !model.isIndexingStopped }
    appear.cancel()
    await appear.value
  }

  @Test("멈춘 뒤 다시 시도를 연달아 눌러도 한 번만 다시 시작하고, 다음 멈춤에서 저절로 다시 시작하지 않는다")
  func repeatedRetryRestartsOnce() async {
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
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }

    model.retryIndexingTapped()
    model.retryIndexingTapped()
    await waitUntil { indexing.runCount == 2 && indexing.activeRunCount == 1 }
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }
    for _ in 0 ..< 100 {
      await Task.yield()
    }

    #expect(indexing.runCount == 2)
    appear.cancel()
    await appear.value
  }

  @Test("인덱싱이 돌고 있을 때 다시 시도는 아무것도 하지 않는다")
  func retryIgnoredWhileRunning() async {
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

    model.retryIndexingTapped()
    // 다시 시도 신호가 남아 있다면, 다음에 멈췄을 때 누르지 않아도 다시 시작한다.
    indexing.finishRuns()
    await waitUntil { model.isIndexingStopped }
    for _ in 0 ..< 100 {
      await Task.yield()
    }

    #expect(indexing.runCount == 1)
    appear.cancel()
    await appear.value
  }
}
