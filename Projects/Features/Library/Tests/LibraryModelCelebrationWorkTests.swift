import IndexingInterface
import Testing
@testable import LibraryFeature

/// 끝낸 수 계산(다시 시도·붙기·기준값).
@MainActor
struct LibraryModelCelebrationWorkTests {
  @Test("다시 시도로 실행이 바뀌어도 앞 실행에서 읽은 글자 수를 더해 끝낸 수를 센다")
  func recognizedTextAccumulatesAcrossRuns() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()

    await fixture.send(.celebration(total: 100, indexed: 100, pending: 40))
    await fixture.send(.celebration(total: 100, indexed: 100, pending: 20, recognized: 20))
    await fixture.stop()
    fixture.model.retryIndexingTapped()
    await fixture.waitForRun(2)
    // 새 실행은 읽은 글자 수를 0 부터 센다: 20 + 10 = 30
    await fixture.send(.celebration(total: 100, indexed: 100, recognized: 10, skippedText: 10))
    await fixture.waitForCelebration()

    appear.cancel()
    await appear.value
  }

  @Test("끝낸 수가 30장 이상일 때만 축하한다", arguments: [(29, false), (30, true)])
  func completedWorkThreshold(recognized: Int, celebrates: Bool) async {
    let baseline = IndexingProgress.celebration(total: 100, indexed: 100, pending: 40)
    let latest = IndexingProgress.celebration(
      total: 100,
      indexed: 100,
      recognized: recognized,
      skippedText: 40 - recognized
    )
    #expect(
      LibraryIndexingCelebration
        .completedWork(baseline: baseline, latest: latest, recognizedInEarlierRuns: 0) == recognized
    )

    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(baseline)
    await fixture.send(latest)
    if celebrates {
      await fixture.waitForCelebration()
    } else {
      #expect(fixture.model.indexingCelebration == nil)
      #expect(fixture.sleep.durations.isEmpty)
    }
    appear.cancel()
    await appear.value
  }

  @Test("이미 돌던 실행에 붙으면 붙기 전에 읽은 글자 수는 끝낸 수에 넣지 않는다")
  func attachedRunExcludesEarlierRecognition() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()

    // 붙을 때 이미 25장을 읽었다: 다 할 때 50 이면 이번 세대에 읽은 것은 25
    await fixture.send(.celebration(total: 100, indexed: 100, pending: 40, recognized: 25))
    await fixture.send(.celebration(total: 100, indexed: 100, recognized: 50, skippedText: 15))
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.isEmpty)

    appear.cancel()
    await appear.value
  }
}
