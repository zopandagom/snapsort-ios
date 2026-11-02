import IndexingInterface
import Testing
@testable import LibraryFeature

/// 분류 완료 축하(docs/ARCHITECTURE.md §4 인덱싱). 세대(화면 진입 한 번)의 첫 진행률로 무장하고, 처음 다 함에서 끝낸 수가 기준 이상이면 축하한다.
/// 머무는 시간은 `ManualSleep` 을 깨워 끝낸다. 인덱싱은 멈춰도 다시 시도를 기다리므로 결과를 확인한 뒤 Task 를 취소해 끝낸다.
@MainActor
struct LibraryModelCelebrationTests {
  @Test("첫 진행률의 남은 일이 30장 이상이면 다 마칠 때 축하하고, 머무는 시간이 지나면 사라진다")
  func celebratesAndDismissesAfterDwell() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()

    await fixture.send(.celebration(total: 100, indexed: 60))
    #expect(fixture.model.indexingCelebration == nil)
    await fixture.send(.celebration(total: 100, indexed: 100))
    await fixture.waitForCelebration()
    #expect(fixture.sleep.durations == [LibraryModel.celebrationDwell])

    fixture.sleep.resumeAll()
    await waitUntil { fixture.model.indexingCelebration == nil }

    appear.cancel()
    await appear.value
  }

  @Test("남은 일은 1단계 남은 수와 2단계 대기 수를 더해 30장 이상이어야 한다")
  func remainingWorkThreshold() async {
    #expect(LibraryIndexingCelebration.remainingWork(.celebration(total: 100, indexed: 80, pending: 10)) == 30)
    #expect(LibraryIndexingCelebration
      .remainingWork(.celebration(total: 100, indexed: 70, skipped: 10, pending: 9)) == 29)
    // 1단계 수가 보관함 수를 넘어도(그사이 지워짐) 남은 일은 음수가 되지 않는다.
    #expect(LibraryIndexingCelebration.remainingWork(.celebration(total: 90, indexed: 100, pending: 5)) == 5)

    // 20 + 10 = 30 → 축하
    let enough = CelebrationFixture()
    let enoughAppear = await enough.appear()
    await enough.send(.celebration(total: 100, indexed: 80, pending: 10))
    await enough.send(.celebration(total: 100, indexed: 100, recognized: 10))
    await enough.waitForCelebration()
    enoughAppear.cancel()
    await enoughAppear.value

    // 20 + 9 = 29 → 없음
    let short = CelebrationFixture()
    let shortAppear = await short.appear()
    await short.send(.celebration(total: 100, indexed: 80, pending: 9))
    await short.send(.celebration(total: 100, indexed: 100, recognized: 9))
    #expect(short.model.indexingCelebration == nil)
    #expect(short.sleep.durations.isEmpty)
    shortAppear.cancel()
    await shortAppear.value
  }

  @Test("첫 진행률이 이미 다 함이면 뒤에 큰 일이 와도 축하하지 않는다")
  func finishedBaselineNeverCelebrates() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()

    await fixture.send(.celebration(total: 100, indexed: 100))
    await fixture.send(.celebration(total: 200, indexed: 100))
    await fixture.send(.celebration(total: 200, indexed: 200))
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.isEmpty)

    appear.cancel()
    await appear.value
  }

  @Test("한 세대에 한 번만 축하하고, 축하 중 같은 다 함 진행률이 다시 와도 머무는 시간을 늘리지 않는다")
  func celebratesOncePerGeneration() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    let finished = IndexingProgress.celebration(total: 100, indexed: 100)

    await fixture.send(.celebration(total: 100, indexed: 50))
    await fixture.send(finished)
    await fixture.waitForCelebration()
    let shown = fixture.model.indexingCelebration

    // 소급이 끝날 때 오는 같은 값 진행률
    await fixture.send(finished)
    #expect(fixture.model.indexingCelebration == shown)
    #expect(fixture.sleep.durations.count == 1)

    fixture.sleep.resumeAll()
    await waitUntil { fixture.model.indexingCelebration == nil }

    // 같은 세대에서 다시 큰 일이 와 다 마쳐도 축하하지 않는다.
    await fixture.send(.celebration(total: 200, indexed: 100))
    await fixture.send(.celebration(total: 200, indexed: 200))
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.count == 1)

    appear.cancel()
    await appear.value
  }

  @Test("축하 중 끝나지 않은 진행률이 오면 축하가 바로 사라진다")
  func unfinishedProgressDismisses() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()

    await fixture.send(.celebration(total: 100, indexed: 50))
    await fixture.send(.celebration(total: 100, indexed: 100))
    await fixture.waitForCelebration()

    // 새 사진이 들어와 진행 카드가 다시 보인다.
    await fixture.send(.celebration(total: 101, indexed: 100))
    #expect(fixture.model.indexingCelebration == nil)

    // 늦게 깨어난 머무는 시간은 아무것도 바꾸지 않는다.
    fixture.sleep.resumeAll()
    await fixture.send(.celebration(total: 101, indexed: 101))
    #expect(fixture.model.indexingCelebration == nil)

    appear.cancel()
    await appear.value
  }

  @Test("멈추면 축하가 사라지고, 다시 시도해 다 마치면 축하한다")
  func stopDismissesAndRetryCelebrates() async {
    // 축하 중 멈춤 → 사라짐
    let shown = CelebrationFixture()
    let shownAppear = await shown.appear()
    await shown.send(.celebration(total: 100, indexed: 50))
    await shown.send(.celebration(total: 100, indexed: 100))
    await shown.waitForCelebration()
    await shown.stop()
    #expect(shown.model.indexingCelebration == nil)
    shownAppear.cancel()
    await shownAppear.value

    // 무장한 채 멈춤 → 멈춤에는 축하 없음 → 다시 시도해 끝까지 가면 축하
    let armed = CelebrationFixture()
    let armedAppear = await armed.appear()
    await armed.send(.celebration(total: 100, indexed: 50))
    await armed.send(.celebration(total: 100, indexed: 70))
    await armed.stop()
    #expect(armed.model.indexingCelebration == nil)
    armed.model.retryIndexingTapped()
    await armed.waitForRun(2)
    await armed.send(.celebration(total: 100, indexed: 100))
    await armed.waitForCelebration()
    armedAppear.cancel()
    await armedAppear.value

    // 무장하지 않은(첫 진행률이 다 함) 채 멈춤 → 다시 시도로 큰 일을 마쳐도 축하 없음
    let unarmed = CelebrationFixture()
    let unarmedAppear = await unarmed.appear()
    await unarmed.send(.celebration(total: 100, indexed: 100))
    await unarmed.stop()
    unarmed.model.retryIndexingTapped()
    await unarmed.waitForRun(2)
    await unarmed.send(.celebration(total: 200, indexed: 100))
    await unarmed.send(.celebration(total: 200, indexed: 200))
    #expect(unarmed.model.indexingCelebration == nil)
    #expect(unarmed.sleep.durations.isEmpty)
    unarmedAppear.cancel()
    await unarmedAppear.value
  }

  @Test("같은 구독 안에서 실행이 바뀌어 읽은 글자 수가 0부터 다시 세어져도 지난 실행에서 읽은 수를 합해 축하한다")
  func recognizedCountSurvivesRunSwapInSameSubscription() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(.celebration(total: 100, indexed: 100, pending: 35))
    await fixture.send(.celebration(total: 100, indexed: 100, pending: 10, recognized: 25))
    // 앞으로 올 때 BG 모드 실행을 새 실행으로 갈아 끼우면 읽은 수가 0부터 다시 센다(구독은 그대로).
    await fixture.send(.celebration(total: 100, indexed: 100, pending: 0, recognized: 10))

    #expect(fixture.model.indexingCelebration != nil)

    appear.cancel()
    await appear.value
  }

  @Test("앱이 뒤에 있는 동안 다 마치면 미뤘다가 앞으로 올 때 보이고, 머무는 시간은 그때부터 잰다")
  func backgroundFinishShowsOnActivation() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(.celebration(total: 100, indexed: 50))

    fixture.model.sceneEnteredBackground()
    await fixture.send(.celebration(total: 100, indexed: 100))
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.isEmpty)

    fixture.model.sceneBecameActive()
    #expect(fixture.model.indexingCelebration != nil)
    await fixture.waitForCelebration()
    #expect(fixture.sleep.durations == [LibraryModel.celebrationDwell])

    fixture.sleep.resumeAll()
    await waitUntil { fixture.model.indexingCelebration == nil }

    appear.cancel()
    await appear.value
  }

  @Test("뒤에서 미룬 축하는 앞으로 오기 전에 끝나지 않은 진행률이나 멈춤이 오면 버린다")
  func pendingDiscardedByProgressOrStop() async {
    // 끝나지 않은 진행률
    let progressed = CelebrationFixture()
    let progressedAppear = await progressed.appear()
    await progressed.send(.celebration(total: 100, indexed: 50))
    progressed.model.sceneEnteredBackground()
    await progressed.send(.celebration(total: 100, indexed: 100))
    await progressed.send(.celebration(total: 101, indexed: 100))
    progressed.model.sceneBecameActive()
    #expect(progressed.model.indexingCelebration == nil)
    #expect(progressed.sleep.durations.isEmpty)
    progressedAppear.cancel()
    await progressedAppear.value

    // 멈춤
    let stopped = CelebrationFixture()
    let stoppedAppear = await stopped.appear()
    await stopped.send(.celebration(total: 100, indexed: 50))
    stopped.model.sceneEnteredBackground()
    await stopped.send(.celebration(total: 100, indexed: 100))
    await stopped.stop()
    stopped.model.sceneBecameActive()
    #expect(stopped.model.indexingCelebration == nil)
    #expect(stopped.sleep.durations.isEmpty)
    stoppedAppear.cancel()
    await stoppedAppear.value
  }

  @Test("화면이 사라지면 축하가 사라지고, 다시 들어오면 새 세대의 첫 진행률로 다시 정한다")
  func disappearClearsAndNewGenerationRearms() async {
    let fixture = CelebrationFixture()
    let firstAppear = await fixture.appear()
    await fixture.send(.celebration(total: 100, indexed: 50))
    await fixture.send(.celebration(total: 100, indexed: 100))
    await fixture.waitForCelebration()

    firstAppear.cancel()
    await firstAppear.value
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.waitingCount == 0)

    let secondAppear = await fixture.appear(runCount: 2)
    #expect(fixture.model.indexingCelebration == nil)
    await fixture.send(.celebration(total: 200, indexed: 100))
    await fixture.send(.celebration(total: 200, indexed: 200))
    await fixture.waitForCelebration()
    #expect(fixture.sleep.durations.count == 2)

    secondAppear.cancel()
    await secondAppear.value
  }

  @Test("인덱서가 없으면 축하 상태가 생기지 않는다")
  func noIndexerNoCelebration() async {
    let fixture = CelebrationFixture(hasIndexer: false)
    let appear = Task { await fixture.model.onAppear() }
    await waitUntil { fixture.photoStore.categoryCoversCallCount == 1 }

    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.isEmpty)

    appear.cancel()
    await appear.value
  }

  @Test("화면 진입의 다른 일이 모두 끝나면 축하 루프도 끝나 화면 진입이 돌아온다")
  func onAppearReturnsWhenOtherWorkFinishes() async {
    let fixture = CelebrationFixture(hasIndexer: false)
    fixture.photoLibrary.finishImageChanges()

    // 취소하지 않는다. 축하 루프가 남아 있으면 여기서 멈춘다.
    await fixture.model.onAppear()

    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.isEmpty)
  }

  // MARK: - 끝낸 수 (docs/ARCHITECTURE.md §4 인덱싱)

  @Test("미룬 이미지만 남은 실행은 다 마쳐도 축하하지 않는다")
  func skippedOnlyRunDoesNotCelebrate() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()

    // 남은 40장이 모두 iCloud 에만 있어 미뤘다: 끝낸 수 0
    await fixture.send(.celebration(total: 100, indexed: 60))
    await fixture.send(.celebration(total: 100, indexed: 60, skipped: 40))
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.isEmpty)

    appear.cancel()
    await appear.value
  }
}

/// 다시 비교: 인덱서는 앞으로 올 때의 새 실행·보관함 전체 다시 비교마다 미룬 장을 다시 남은 일로 센다(docs/ARCHITECTURE.md §4 인덱싱).
/// F 는 미룬 장이 있는 다 함, p1 은 새 실행 첫 진행률(미룬 1단계 3장이 남은 일로, 미룬 2단계 2장이 대기로 돌아옴), F2 는 다시 비교 뒤 다 함.
@MainActor
struct LibraryModelCelebrationRecomparisonTests {
  private let baseline = IndexingProgress.celebration(total: 100, indexed: 40)
  private let finished = IndexingProgress.celebration(total: 100, indexed: 97, skipped: 3, skippedText: 2)
  private let recomparing = IndexingProgress.celebration(total: 100, indexed: 97, pending: 2)

  @Test("뒤에서 다 마친 축하는 앞으로 와 새 실행이 미룬 장을 다시 세는 첫 진행률이 와도 머무는 시간을 채운다")
  func backgroundCelebrationSurvivesRecomparison() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(self.baseline)

    fixture.model.sceneEnteredBackground()
    await fixture.send(self.finished)
    fixture.model.sceneBecameActive()
    await fixture.waitForCelebration()
    let id = fixture.model.indexingCelebration?.id

    await fixture.send(self.recomparing)
    #expect(fixture.model.indexingCelebration?.id == id)
    #expect(fixture.model.isIndexing)
    #expect(fixture.sleep.durations == [LibraryModel.celebrationDwell])

    // 다시 비교가 끝나 같은 다 함이 와도 머무는 시간을 늘리지 않는다.
    await fixture.send(self.finished)
    #expect(fixture.model.indexingCelebration?.id == id)
    #expect(fixture.sleep.durations.count == 1)

    fixture.sleep.resumeAll()
    await waitUntil { fixture.model.indexingCelebration == nil }

    // 무장은 처음 다 함에서 풀렸으므로 다시 축하하지 않는다.
    await fixture.send(self.finished)
    #expect(fixture.model.indexingCelebration == nil)
    #expect(fixture.sleep.durations.count == 1)

    appear.cancel()
    await appear.value
  }

  /// 앞으로 온 뒤 held 값을 isSceneActive 참으로 받는 실제로 흔한 경로와 앞의 `.reloadAll` 경로를 함께 흉내 낸다.
  @Test("앞에서 받은 다 함의 축하 중 미룬 장이 남은 일로 돌아오는 다시 비교 진행률이 와도 축하는 남는다")
  func foregroundCelebrationSurvivesRecomparison() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(self.baseline)
    await fixture.send(self.finished)
    await fixture.waitForCelebration()
    let id = fixture.model.indexingCelebration?.id

    await fixture.send(self.recomparing)
    #expect(fixture.model.indexingCelebration?.id == id)

    appear.cancel()
    await appear.value
  }

  @Test(
    "축하 중 끝나지 않은 진행률은 보관함 수가 늘었거나 남은 일이 축하 때 미룬 수보다 많을 때만 축하를 지운다",
    arguments: [
      // 남은 일 3 + 2 = 5: 미룬 수(5) 이하라 남는다.
      (IndexingProgress.celebration(total: 100, indexed: 97, pending: 2), true),
      // 남은 일 4 + 2 = 6: 보관함 수는 그대로지만 미룬 수보다 많다(삭제와 추가가 함께 옴).
      (IndexingProgress.celebration(total: 100, indexed: 96, pending: 2), false),
      // 남은 일 1: 미룬 수 이하지만 보관함 수가 늘었다(새 사진).
      (IndexingProgress.celebration(total: 101, indexed: 97, skipped: 3), false),
    ]
  )
  func unfinishedProgressDismissesOnlyNewWork(progress: IndexingProgress, remains: Bool) async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(self.baseline)
    await fixture.send(self.finished)
    await fixture.waitForCelebration()

    await fixture.send(progress)
    #expect((fixture.model.indexingCelebration != nil) == remains)

    appear.cancel()
    await appear.value
  }

  @Test("다시 비교 중 멈추면 축하가 사라진다")
  func stopDuringRecomparisonDismisses() async {
    let fixture = CelebrationFixture()
    let appear = await fixture.appear()
    await fixture.send(self.baseline)
    await fixture.send(self.finished)
    await fixture.waitForCelebration()
    await fixture.send(self.recomparing)
    #expect(fixture.model.indexingCelebration != nil)

    await fixture.stop()
    #expect(fixture.model.indexingCelebration == nil)

    appear.cancel()
    await appear.value
  }
}
