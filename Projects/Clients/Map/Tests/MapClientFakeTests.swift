import MapInterface
import MapTesting
import Synchronization
import Testing

struct MapClientFakeTests {
  @Test("받은 주소를 차례로 기록하고 정한 결과를 돌려준다")
  func recordsAddresses() async {
    let fake = MapClientFake()
    let failing = MapClientFake(openResult: false)

    #expect(await fake.openInMaps(address: "세종대로 110"))
    #expect(await fake.openInMaps(address: "테헤란로 1"))
    #expect(await failing.openInMaps(address: "세종대로 110") == false)

    #expect(fake.openedAddresses == ["세종대로 110", "테헤란로 1"])
    #expect(failing.openedAddresses == ["세종대로 110"])
  }

  @Test("훅이 기다리는 동안 이미 주소를 기록했고, 훅이 끝나면 정한 결과를 돌려준다")
  func recordsBeforeHook() async {
    let entered = Mutex(false)
    let (release, continuation) = AsyncStream.makeStream(of: Void.self)
    let fake = MapClientFake(openResult: false) {
      entered.withLock { $0 = true }
      for await _ in release {}
    }

    let open = Task { await fake.openInMaps(address: "세종대로 110") }
    while !entered.withLock({ $0 }) {
      await Task.yield()
    }
    #expect(fake.openedAddresses == ["세종대로 110"])

    continuation.finish()
    #expect(await open.value == false)
  }
}
