import PasteboardInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 클립보드에 쓰지 않고 받은 글자를 기록한다.
/// 기록이 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class PasteboardClientFake: PasteboardClient {
  private let onCopy: @Sendable () async -> Void
  private let state = Mutex<[String]>([])

  /// - Parameter onCopy: `copy` 가 글자를 기록한 뒤, 돌아가기 전에 기다려 부른다. 늦게 끝나는 복사를 흉내 낸다.
  public init(onCopy: @escaping @Sendable () async -> Void = {}) {
    self.onCopy = onCopy
  }

  /// `copy` 에 넘긴 글자를 부른 순서대로.
  public var copiedTexts: [String] {
    self.state.withLock { $0 }
  }

  public func copy(_ text: String) async {
    self.state.withLock { $0.append(text) }
    await self.onCopy()
  }
}
