import Core
import Foundation
import IndexingInterface
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import IndexingImpl

/// 공유 실행기 (docs/ARCHITECTURE.md §4 인덱싱): 앞 구독자와 BG 작업이 실행 하나를 함께 쓰고, 앱이 비활성이 되면 저장소 출입을 닫고 멈춘다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingExecutorTests {
  @Test("앞 구독 둘과 BG 실행이 실행 하나를 함께 쓰고 같은 이미지를 두 번 분석·저장하지 않는다")
  func sharesOneRun() async {
    let release = StuckGate()
    let fixture = Fixture(
      library: (0 ..< 3).map { .stub(id: "image-\($0)") },
      onRecognize: { _ in await release.wait() }
    )
    let indexing = fixture.indexing

    let background = Task { await indexing.runInBackground(shouldYield: { false }, progress: { _ in }) }
    let first = ProgressConsumer(indexing)
    let second = ProgressConsumer(indexing)
    await eventually { !first.received.isEmpty && !second.received.isEmpty }
    #expect(fixture.photoLibrary.imageChangesSubscriberCount == 1)
    release.open()

    let result = await background.value
    await first.waitUntilFinished()
    await second.waitUntilFinished()

    #expect(result == IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: true))
    #expect(fixture.photoLibrary.imageChangesSubscriberCount == 1)
    #expect(fixture.thumbnailLoadIDs.sorted() == ["image-0", "image-1", "image-2"])
    #expect(fixture.photoLibrary.largestLoadIDs.sorted() == ["image-0", "image-1", "image-2"])
    first.cancel()
    second.cancel()
  }

  @Test("멈춘 실행이 Vision 에 묶여 있어도 다시 활성이 되면 새 실행이 돌고, 늦게 돌아온 옛 실행은 저장소를 부르지 않는다")
  func staleRunNeverReachesStore() async {
    let stuck = StuckGate()
    let calls = Mutex(0)
    let fixture = Fixture(
      library: [.stub(id: "a")],
      onRecognize: { _ in
        let call = calls.withLock { value in
          defer { value += 1 }
          return value
        }
        // 첫 실행의 OCR 만 취소에 응답하지 않고 묶인다.
        if call == 0 {
          await stuck.wait()
        }
      }
    )
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await eventually { calls.withLock { $0 } == 1 }

    indexing.appActivityChanged(isActive: false)
    await indexing.waitUntilStoreReleased()
    indexing.appActivityChanged(isActive: true)
    await consumer.waitUntilFinished()
    let savedBeforeRelease = fixture.store.savedBatches.count
    let receivedBeforeRelease = consumer.received

    stuck.open()
    // 옛 실행이 끝나면 그 실행의 변경 구독도 끝난다.
    await eventually { fixture.photoLibrary.imageChangesSubscriberCount == 1 }

    #expect(fixture.store.savedBatches.count == savedBeforeRelease)
    #expect(consumer.received == receivedBeforeRelease)
    #expect(fixture.photoLibrary.largestLoadIDs == ["a", "a"])
    consumer.cancel()
  }

  @Test("비활성이 되면 진행 중 저장이 끝난 뒤에 손을 떼고, 그 뒤 저장소를 부르지 않으며, 다시 활성이면 저장된 데서 이어 간다")
  func pausesAfterInFlightSave() async {
    let entered = Gate()
    let release = StuckGate()
    let saves = Mutex(0)
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      onSaveGifticons: { _ in
        // 첫 저장만 막는다(취소에 응답하지 않는 저장소 호출).
        if saves.withLock({ value in
          defer { value += 1 }
          return value == 0
        }) {
          entered.open()
          await release.wait()
        }
      },
      batchSize: 1
    )
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await entered.wait()

    indexing.appActivityChanged(isActive: false)
    let released = Flag()
    let waiting = Task {
      await indexing.waitUntilStoreReleased()
      released.set()
    }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!released.isSet)

    release.open()
    await waiting.value
    try? await Task.sleep(for: .milliseconds(50))
    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [["a"]])

    indexing.appActivityChanged(isActive: true)
    await eventually { fixture.store.savedGifticonBatches.count == 2 }
    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [["a"], ["b"]])
    consumer.cancel()
  }

  @Test("비활성 동안 BG 실행의 진행률은 앞 구독자에 가지 않고, 다시 활성이면 최신 값을 먼저 받는다")
  func holdsProgressWhileInactive() async {
    let fixture = Fixture(library: [.stub(id: "a"), .stub(id: "b")])
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)
    let background = Received<IndexingProgress>()

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { background.append($0) })

    #expect(result.hasRemainingWork == false)
    #expect(consumer.received.isEmpty)
    #expect(background.all.last?.isFinished == true)

    indexing.appActivityChanged(isActive: true)
    await eventually { !consumer.received.isEmpty }
    #expect(consumer.received.first == background.all.last)
    consumer.cancel()
  }

  @Test("앞 실행이 할 일을 마치고 쉬는 중이면 BG 실행은 바로 할 일 없음으로 돌아온다")
  func returnsImmediatelyWhenIdle() async {
    let fixture = Fixture(library: [.stub(id: "a")])
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await consumer.waitUntilFinished()
    // 유휴 표시는 마지막 진행률 직후에 선다.
    try? await Task.sleep(for: .milliseconds(20))

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })

    #expect(result == IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: false))
    consumer.cancel()
  }

  @Test("할 일이 없는 콜드 BG 실행은 여행 교체만 하고 바뀐 것 없음으로 돌아온다")
  func returnsNoChangeWhenNothingToDo() async {
    let fixture = Fixture(library: [.stub(id: "a")], stored: [indexed("a")])
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })

    #expect(result == IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: false))
    #expect(fixture.store.replaceTripsCount == 1)
  }

  @Test("BG 실행은 할 일을 마치면 쓴 것이 있었다고 돌려준다")
  func reportsStoreChangeWhenWorkDone() async {
    let fixture = Fixture(library: [.stub(id: "a")])
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })

    #expect(result == IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: true))
    #expect(fixture.store.images.map(\.id) == ["a"])
  }

  @Test("저장 도중 BG 실행을 취소하면 저장이 끝난 뒤에 남은 일로 돌아오고, 그 뒤 저장소를 부르지 않는다")
  func cancellationWaitsForInFlightSave() async {
    let entered = Gate()
    let release = StuckGate()
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      onSaveGifticons: { _ in
        entered.open()
        await release.wait()
      },
      batchSize: 1
    )
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let returned = Flag()
    let background = Task {
      let result = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })
      returned.set()
      return result
    }
    await entered.wait()

    background.cancel()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!returned.isSet)

    release.open()
    let result = await background.value
    try? await Task.sleep(for: .milliseconds(50))

    #expect(result.hasRemainingWork)
    #expect(fixture.store.savedGifticonBatches.count == 1)
  }

  @Test("비활성 중 저장소가 실패하면 앞 구독자 스트림을 끝내지 않고, 활성에서 실패하면 지금처럼 끝낸다")
  func keepsSubscribersWhenStoreFailsInBackground() async {
    let fixture = Fixture(library: [.stub(id: "a")], storeError: .failed)
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })
    try? await Task.sleep(for: .milliseconds(20))

    #expect(result == IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
    #expect(!consumer.isFinished)

    indexing.appActivityChanged(isActive: true)
    await consumer.waitUntilEnded()
  }

  @Test("BG 모드에서 양보해야 하면 진행 중 배치를 저장한 뒤 남은 일로 돌아온다")
  func yieldsAfterSavingBatch() async {
    let fixture = Fixture(library: (0 ..< 3).map { .stub(id: "image-\($0)") }, batchSize: 1)
    let indexing = fixture.indexing
    let shouldYield = Flag()
    indexing.appActivityChanged(isActive: false)

    let result = await indexing.runInBackground(
      shouldYield: { shouldYield.isSet },
      progress: { _ in shouldYield.set() }
    )

    #expect(result == IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: true))
    #expect(fixture.store.savedBatches.count == 1)
  }

  @Test("쉬는 실행에 새로 구독하면 최신 진행률을 바로 받는다")
  func newSubscriberGetsLatest() async {
    let fixture = Fixture(library: [.stub(id: "a")])
    let indexing = fixture.indexing
    let first = ProgressConsumer(indexing)
    await first.waitUntilFinished()

    let second = ProgressConsumer(indexing)
    await eventually { !second.received.isEmpty }

    #expect(second.received.first?.isFinished == true)
    #expect(fixture.photoLibrary.imageChangesSubscriberCount == 1)
    first.cancel()
    second.cancel()
  }

  @Test("비활성이면 앞 구독만으로는 돌지 않고, 다시 활성이면 새 실행이 돈다")
  func resumesOnActivation() async {
    let fixture = Fixture(library: [.stub(id: "a")])
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(fixture.thumbnailLoadIDs.isEmpty)

    indexing.appActivityChanged(isActive: true)
    await consumer.waitUntilFinished()

    #expect(fixture.store.images.map(\.id) == ["a"])
    consumer.cancel()
  }

  @Test("같은 활성 값이 다시 와도 도는 실행을 다시 시작하지 않는다")
  func ignoresRepeatedActivity() async {
    let fixture = Fixture(library: [.stub(id: "a")])
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await consumer.waitUntilFinished()

    indexing.appActivityChanged(isActive: true)
    try? await Task.sleep(for: .milliseconds(20))

    #expect(fixture.thumbnailLoadIDs == ["a"])
    #expect(fixture.analysis.activityChanges.isEmpty)
    consumer.cancel()
  }
}

// MARK: - 준비

/// 다른 Task 에서 값을 모은다.
final class Received<Value: Sendable>: Sendable {
  private let values = Mutex<[Value]>([])

  func append(_ value: Value) {
    self.values.withLock { $0.append(value) }
  }

  var all: [Value] {
    self.values.withLock { $0 }
  }
}

/// 한 번 켜면 켜진 채인 표시.
final class Flag: Sendable {
  private let value = Mutex(false)

  func set() {
    self.value.withLock { $0 = true }
  }

  var isSet: Bool {
    self.value.withLock { $0 }
  }
}

/// 열릴 때까지 기다리고 Task 취소에 응답하지 않는 문. 취소에 늦게 응답하는 Vision·저장소 호출을 흉내 낸다.
final class StuckGate: Sendable {
  private let isOpen = Mutex(false)

  func open() {
    self.isOpen.withLock { $0 = true }
  }

  func wait() async {
    while !self.isOpen.withLock({ $0 }) {
      try? await Task.sleep(for: .milliseconds(1))
    }
  }
}

/// `run()` 을 구독해 진행률을 모으는 Task.
final class ProgressConsumer: Sendable {
  private let values = Received<IndexingProgress>()
  private let ended = Flag()
  private let task: Task<Void, Never>

  init(_ indexing: IndexingClientImpl) {
    let values = self.values
    let ended = self.ended
    self.task = Task {
      for await progress in indexing.run() {
        values.append(progress)
      }
      ended.set()
    }
  }

  var received: [IndexingProgress] {
    self.values.all
  }

  /// 스트림이 끝났는지.
  var isFinished: Bool {
    self.ended.isSet
  }

  func waitUntilFinished() async {
    await eventually { self.received.last?.isFinished == true }
  }

  func waitUntilEnded() async {
    await self.task.value
  }

  func cancel() {
    self.task.cancel()
  }
}

/// 조건이 참이 될 때까지 기다린다.
func eventually(_ condition: () -> Bool) async {
  while !condition() {
    try? await Task.sleep(for: .milliseconds(1))
  }
}
