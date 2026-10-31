import BackgroundIndexingInterface
import BackgroundIndexingTesting
import Testing

@MainActor
struct BackgroundIndexingClientFakeTests {
  @Test("처음에는 기록이 없다")
  func startsEmpty() {
    let fake = BackgroundIndexingClientFake()

    #expect(fake.events.isEmpty)
  }

  @Test("이벤트를 부른 순서대로 기록한다")
  func recordsEventsInOrder() {
    let fake = BackgroundIndexingClientFake()

    fake.appDidEnterBackground()
    fake.appDidBecomeActive()
    fake.appDidEnterBackground()

    #expect(fake.events == [.didEnterBackground, .didBecomeActive, .didEnterBackground])
  }

  @Test("계속 처리 요청을 기록하고 문구를 두며, 결과에 따라 상태를 바꾼다")
  func recordsContinuedRequests() {
    let fake = BackgroundIndexingClientFake()
    let text = ContinuedIndexingText(title: { _ in "제목" }, subtitle: { _ in "부제" })
    #expect(fake.continuedIndexingState == .idle)

    #expect(fake.requestContinuedIndexing(text: text) == .started)
    #expect(fake.continuedIndexingState == .active)
    #expect(fake.events == [.continuedIndexingRequested])
    let status = ContinuedIndexingStatus(stage: .preparing, doneCount: 0, totalCount: 0)
    #expect(fake.lastContinuedText?.title(status) == "제목")

    fake.continuedIndexingState = .idle
    fake.continuedRequestResult = .temporarilyUnavailable
    #expect(fake.requestContinuedIndexing(text: text) == .temporarilyUnavailable)
    #expect(fake.continuedIndexingState == .idle)

    fake.continuedRequestResult = .unavailable
    #expect(fake.requestContinuedIndexing(text: text) == .unavailable)
    #expect(fake.continuedIndexingState == .unsupported)
    #expect(fake.events.count == 3)
  }

  @Test("처음 상태와 결과를 정할 수 있다")
  func configuresInitialState() {
    let fake = BackgroundIndexingClientFake(continuedIndexingState: .unsupported, continuedRequestResult: .unavailable)

    #expect(fake.continuedIndexingState == .unsupported)
    #expect(fake.continuedRequestResult == .unavailable)
  }
}
