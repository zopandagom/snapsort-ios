import Foundation
import IndexingInterface
import Testing
@testable import IndexingImpl

/// 공유 실행기에 BG 작업이 붙을 때 최신 진행률을 먼저 받는지 (계속 처리 작업이 시작하자마자 확정 진행률을 보이게).
@Suite(.timeLimit(.minutes(1)))
struct IndexingExecutorHoldProgressTests {
  @Test("도는 실행에 BG 실행이 붙으면 그 실행의 최신 진행률을 바로 한 번 받는다")
  func newHoldGetsLatestOfRunningRun() async {
    let release = StuckGate()
    let fixture = Fixture(
      library: (0 ..< 3).map { .stub(id: "image-\($0)") },
      onRecognize: { _ in await release.wait() }
    )
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await eventually { !consumer.received.isEmpty }
    // 실행이 OCR 에 묶이기 전 진행률이 앞 구독자에 다 닿게 잠깐 둔다. 묶인 뒤로는 새 진행률이 없다.
    try? await Task.sleep(for: .milliseconds(100))
    let latest = consumer.received.last
    let background = Received<IndexingProgress>()

    let hold = Task { await indexing.runInBackground(shouldYield: { false }, progress: { background.append($0) }) }
    await eventually { !background.all.isEmpty }
    #expect(background.all.count == 1)
    #expect(background.all.first == latest)

    release.open()
    _ = await hold.value
    #expect(background.all.first == latest)
    consumer.cancel()
  }

  @Test("앞 실행이 쉬는 중이면 BG 실행은 최신 진행률을 받지 않고 돌아온다")
  func idleRunSendsNoLatestToHold() async {
    let fixture = Fixture(library: [.stub(id: "a")])
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await consumer.waitUntilFinished()
    // 유휴 표시는 마지막 진행률 직후에 선다.
    try? await Task.sleep(for: .milliseconds(20))
    let background = Received<IndexingProgress>()

    _ = await indexing.runInBackground(shouldYield: { false }, progress: { background.append($0) })

    #expect(background.all.isEmpty)
    consumer.cancel()
  }
}
