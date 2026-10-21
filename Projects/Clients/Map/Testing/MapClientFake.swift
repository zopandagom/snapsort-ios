import MapInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 지도 앱을 열지 않고 받은 주소를 기록한다.
/// 기록이 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class MapClientFake: MapClient {
  private let openResult: Bool
  private let onOpen: @Sendable () async -> Void
  private let state = Mutex<[String]>([])

  /// - Parameters:
  ///   - openResult: `openInMaps` 가 돌려줄 값. false 면 지도 앱을 열지 못한 경우를 흉내 낸다(그래도 주소는 기록한다).
  ///   - onOpen: `openInMaps` 가 주소를 기록한 뒤, 돌려주기 전에 기다려 부른다. 늦게 끝나는 지도 앱 열기를 흉내 낸다.
  public init(openResult: Bool = true, onOpen: @escaping @Sendable () async -> Void = {}) {
    self.openResult = openResult
    self.onOpen = onOpen
  }

  /// `openInMaps` 에 넘긴 주소를 부른 순서대로.
  public var openedAddresses: [String] {
    self.state.withLock { $0 }
  }

  public func openInMaps(address: String) async -> Bool {
    self.state.withLock { $0.append(address) }
    await self.onOpen()
    return self.openResult
  }
}
