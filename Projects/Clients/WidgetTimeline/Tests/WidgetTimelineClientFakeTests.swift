import Testing
import WidgetTimelineInterface
import WidgetTimelineTesting

struct WidgetTimelineClientFakeTests {
  @Test("처음에는 요청 수가 0이다")
  func startsWithoutRequests() {
    let fake = WidgetTimelineClientFake()

    #expect(fake.reloadCount == 0)
  }

  @Test("갱신 요청 수를 기록한다")
  func countsReloads() {
    let fake = WidgetTimelineClientFake()

    fake.reloadExpiryWidget()
    fake.reloadExpiryWidget()

    #expect(fake.reloadCount == 2)
  }
}
