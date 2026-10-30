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
}
