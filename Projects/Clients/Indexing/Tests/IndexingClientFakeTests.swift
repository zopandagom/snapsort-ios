import IndexingInterface
import IndexingTesting
import Synchronization
import Testing

struct IndexingClientFakeTests {
  @Test("정해 둔 진행률을 차례로 보내고 끝낸다")
  func sendsConfiguredProgress() async {
    let progress = [
      IndexingProgress(totalCount: 2, indexedCount: 0, skippedCount: 0),
      IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 1),
    ]
    let fake = IndexingClientFake(progress: progress)

    var received: [IndexingProgress] = []
    for await value in fake.run() {
      received.append(value)
    }

    #expect(received == progress)
    #expect(received.last?.isFinished == true)
    #expect(fake.activeRunCount == 0)
  }

  @Test("끝나지 않게 정하면 구독을 끝낼 때까지 이어지고, 끝나면 돌고 있는 수에서 뺀다")
  func keepsRunningUntilCancelled() async {
    let fake = IndexingClientFake(
      progress: [IndexingProgress(totalCount: 1, indexedCount: 0, skippedCount: 0)],
      finishesAfterProgress: false
    )

    let task = Task {
      for await _ in fake.run() {}
    }
    while fake.activeRunCount == 0 {
      await Task.yield()
    }
    task.cancel()
    await task.value

    #expect(fake.activeRunCount == 0)
  }

  @Test("돌고 있는 스트림에 진행률을 더 보내고, 끝내면 받는 쪽 반복이 끝난다")
  func sendsProgressAndFinishesRuns() async {
    let fake = IndexingClientFake(finishesAfterProgress: false)
    let sent = IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 0)

    let task = Task {
      var received: [IndexingProgress] = []
      for await value in fake.run() {
        received.append(value)
      }
      return received
    }
    while fake.activeRunCount == 0 {
      await Task.yield()
    }
    fake.sendProgress(sent)
    fake.finishRuns()

    #expect(await task.value == [sent])
    #expect(fake.activeRunCount == 0)
    #expect(fake.runCount == 1)
  }

  @Test("BG 작업 쪽 호출을 순서대로 기록하고, 정해 둔 진행률을 보낸 뒤 정해 둔 결과를 돌려준다")
  func recordsBackgroundCalls() async {
    let sent = IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0)
    let result = IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: true)
    let forwarded = Mutex<[IndexingClientFake.Event]>([])
    let fake = IndexingClientFake(
      backgroundProgress: [sent],
      backgroundResult: result,
      onEvent: { event in forwarded.withLock { $0.append(event) } }
    )
    let received = Mutex<[IndexingProgress]>([])

    fake.appActivityChanged(isActive: false)
    await fake.waitUntilStoreReleased()
    let returned = await fake.runInBackground(shouldYield: { true }, progress: { value in
      received.withLock { $0.append(value) }
    })

    #expect(returned == result)
    #expect(received.withLock { $0 } == [sent])
    #expect(fake.activityChanges == [false])
    #expect(fake.lastShouldYield == true)
    #expect(fake.events == [
      .appActivityChanged(isActive: false),
      .waitUntilStoreReleasedStarted,
      .waitUntilStoreReleasedReturned,
      .runInBackgroundStarted,
      .runInBackgroundReturned(result),
    ])
    #expect(forwarded.withLock { $0 } == fake.events)
  }

  @Test("결과를 정하지 않으면 끝낼 때까지 기다리고, 그동안 진행률을 더 보낼 수 있다")
  func waitsUntilBackgroundRunFinished() async {
    let fake = IndexingClientFake(backgroundResult: nil)
    let sent = IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 0)
    let result = IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: true)
    let received = Mutex<[IndexingProgress]>([])

    let task = Task {
      await fake.runInBackground(shouldYield: { false }, progress: { value in
        received.withLock { $0.append(value) }
      })
    }
    while fake.activeBackgroundRunCount == 0 {
      await Task.yield()
    }
    fake.sendBackgroundProgress(sent)
    fake.finishBackgroundRuns(with: result)

    #expect(await task.value == result)
    #expect(received.withLock { $0 } == [sent])
    #expect(fake.activeBackgroundRunCount == 0)
  }

  @Test("기다리는 BG 실행을 취소하면 남은 일로 돌아오고 취소를 기록한다")
  func returnsRemainingWhenCancelled() async {
    let fake = IndexingClientFake(backgroundResult: nil)

    let task = Task { await fake.runInBackground(shouldYield: { false }, progress: { _ in }) }
    while fake.activeBackgroundRunCount == 0 {
      await Task.yield()
    }
    task.cancel()

    #expect(await task.value == IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
    #expect(fake.events.contains(.runInBackgroundCancelled))
  }

  @Test("저장소 손 떼기를 막아 두면 풀 때까지 기다린다")
  func holdsStoreReleaseUntilReleased() async {
    let fake = IndexingClientFake(holdsStoreRelease: true)

    let task = Task { await fake.waitUntilStoreReleased() }
    while !fake.events.contains(.waitUntilStoreReleasedStarted) {
      await Task.yield()
    }
    #expect(!fake.events.contains(.waitUntilStoreReleasedReturned))
    fake.releaseStore()
    await task.value

    #expect(fake.events.last == .waitUntilStoreReleasedReturned)
  }
}
