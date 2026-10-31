import BackgroundIndexingInterface
import BackgroundIndexingTesting
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

// 계속 처리 분류가 도는 동안의 안내 줄("홈으로 나가도 이어서 분류합니다"). 파일 길이 제한 때문에 나눈다.
extension LibraryModelContinuedIndexingTests {
  @Test("첫 분류를 자동 요청하면 버튼 대신 안내 줄을 보인다")
  func autoRequestShowsNotice() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .authorized)
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(photoLibrary: photoLibrary, indexing: indexing, backgroundIndexing: backgroundIndexing)
    _ = await photoLibrary.requestAccess()
    let appear = await Self.appear(model, indexing: indexing)
    #expect(!model.showsContinuingInBackgroundNotice)

    await Self.send(Self.classifying, to: model, indexing: indexing)

    #expect(Self.requestCount(backgroundIndexing) == 1)
    #expect(model.showsContinuingInBackgroundNotice)
    #expect(!model.showsContinueInBackgroundButton)
    await cancelAndWait(appear)
  }

  @Test("버튼을 눌러 시작하면 버튼 대신 안내 줄을 보이고, 시작하지 못하면 보이지 않는다", arguments: [
    (ContinuedIndexingRequestResult.started, true),
    (.temporarilyUnavailable, false),
    (.unavailable, false),
  ])
  func tapShowsNoticeWhenStarted(result: ContinuedIndexingRequestResult, showsNotice: Bool) async {
    let running = await Self.indexingModel(
      backgroundIndexing: BackgroundIndexingClientFake(continuedRequestResult: result)
    )
    #expect(!running.model.showsContinuingInBackgroundNotice)

    running.model.continueInBackgroundTapped()

    #expect(running.model.showsContinuingInBackgroundNotice == showsNotice)
    #expect(!(running.model.showsContinuingInBackgroundNotice && running.model.showsContinueInBackgroundButton))
    await cancelAndWait(running.appear)
  }

  @Test("안내 줄은 글자 읽는 중에도 보이고, 계속 처리가 요청되지 않았거나 쓸 수 없으면 보이지 않는다", arguments: [
    (ContinuedIndexingState.active, true),
    (.idle, false),
    (.unsupported, false),
  ])
  func noticeFollowsState(state: ContinuedIndexingState, showsNotice: Bool) async {
    let running = await Self.indexingModel(
      backgroundIndexing: BackgroundIndexingClientFake(continuedIndexingState: state),
      progress: IndexingProgress(
        totalCount: 3, indexedCount: 3, skippedCount: 0, pendingTextCount: 2, recognizedTextCount: 1
      )
    )

    #expect(running.model.showsContinuingInBackgroundNotice == showsNotice)
    await cancelAndWait(running.appear)
  }

  @Test("다 분석했거나 분류가 멈추면 안내 줄을 숨긴다")
  func noticeHiddenWhenFinishedOrStopped() async {
    let running = await Self.indexingModel(
      backgroundIndexing: BackgroundIndexingClientFake(continuedIndexingState: .active)
    )
    #expect(running.model.showsContinuingInBackgroundNotice)

    await Self.send(Self.finished, to: running.model, indexing: running.indexing)
    #expect(!running.model.showsContinuingInBackgroundNotice)

    await Self.send(Self.classifying, to: running.model, indexing: running.indexing)
    #expect(running.model.showsContinuingInBackgroundNotice)
    running.indexing.finishRuns()
    await waitUntil { running.model.isIndexingStopped }
    #expect(!running.model.showsContinuingInBackgroundNotice)
    await cancelAndWait(running.appear)
  }

  @Test("앱이 앞으로 와 계속 처리가 끝났으면 안내 줄 대신 버튼이 다시 보인다")
  func noticeTurnsBackIntoButton() async {
    let backgroundIndexing = BackgroundIndexingClientFake()
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)
    running.model.continueInBackgroundTapped()
    #expect(running.model.showsContinuingInBackgroundNotice)

    running.model.sceneEnteredBackground()
    backgroundIndexing.continuedIndexingState = .idle
    running.model.sceneBecameActive()

    #expect(!running.model.showsContinuingInBackgroundNotice)
    #expect(running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }
}
