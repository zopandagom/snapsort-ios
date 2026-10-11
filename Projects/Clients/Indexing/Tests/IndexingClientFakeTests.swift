import IndexingInterface
import IndexingTesting
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
}
