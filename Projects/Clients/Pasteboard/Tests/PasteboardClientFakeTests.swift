import PasteboardInterface
import PasteboardTesting
import Synchronization
import Testing

struct PasteboardClientFakeTests {
  @Test("복사한 글자를 차례로 기록한다")
  func recordsCopiedTexts() async {
    let fake = PasteboardClientFake()

    await fake.copy("1234-5678-9012")
    await fake.copy("110-123-456789")

    #expect(fake.copiedTexts == ["1234-5678-9012", "110-123-456789"])
  }

  @Test("훅이 기다리는 동안 이미 글자를 기록했다")
  func recordsBeforeHook() async {
    let entered = Mutex(false)
    let (release, continuation) = AsyncStream.makeStream(of: Void.self)
    let fake = PasteboardClientFake {
      entered.withLock { $0 = true }
      for await _ in release {}
    }

    let copy = Task { await fake.copy("1234-5678-9012") }
    while !entered.withLock({ $0 }) {
      await Task.yield()
    }
    #expect(fake.copiedTexts == ["1234-5678-9012"])

    continuation.finish()
    await copy.value
  }
}
