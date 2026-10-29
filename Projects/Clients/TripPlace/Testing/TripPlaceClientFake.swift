import Foundation
import Synchronization
import TripPlaceInterface

/// 테스트와 Example 앱용 대역. 미리 받기 회차를 부른 로캘을 기록하고, 정한 동안 매달렸다가 돌아온다.
/// 캐시 쓰기 신호는 `sendPlaceChange()` 로 흉내 낸다.
/// 기록과 구독이 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class TripPlaceClientFake: TripPlaceClient {
  private let onPrefetch: @Sendable (Int) async -> Void
  private let state = Mutex(State())

  private struct State {
    var prefetchLocaleIdentifiers: [String] = []
    var cancelledPrefetchCount = 0
    var nextSubscriberID = 0
    var subscribers: [Int: AsyncStream<Void>.Continuation] = [:]
  }

  /// - Parameter onPrefetch: `prefetchPlaces(locale:)` 가 로캘을 기록한 뒤, 돌아오기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///   오래 걸리는 회차를 흉내 낸다. 취소를 흉내 내려면 Task 취소를 받는 기다림(`Task.sleep` 등)을 쓴다.
  public init(onPrefetch: @escaping @Sendable (Int) async -> Void = { _ in }) {
    self.onPrefetch = onPrefetch
  }

  /// `prefetchPlaces(locale:)` 에 넘긴 로캘 식별자를 부른 순서대로.
  public var prefetchLocaleIdentifiers: [String] {
    self.state.withLock { $0.prefetchLocaleIdentifiers }
  }

  /// `onPrefetch` 를 기다린 뒤 부른 Task 가 취소돼 있던 호출 수. 회차가 취소됐는지 확인하는 데 쓴다.
  public var cancelledPrefetchCount: Int {
    self.state.withLock { $0.cancelledPrefetchCount }
  }

  /// 아직 끝나지 않은 `placeChanges()` 구독 수. 신호를 보내기 전에 구독이 섰는지 확인하는 데 쓴다.
  public var activeSubscriberCount: Int {
    self.state.withLock { $0.subscribers.count }
  }

  public func prefetchPlaces(locale: Locale) async {
    let index = self.state.withLock { state in
      state.prefetchLocaleIdentifiers.append(locale.identifier)
      return state.prefetchLocaleIdentifiers.count - 1
    }
    await self.onPrefetch(index)
    if Task.isCancelled {
      self.state.withLock { $0.cancelledPrefetchCount += 1 }
    }
  }

  public func placeChanges() async -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let id = self.state.withLock { state in
      defer { state.nextSubscriberID += 1 }
      return state.nextSubscriberID
    }
    // 정리 핸들러를 먼저 달고 등록한다(IndexingClientFake 와 같은 순서).
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
    }
    self.state.withLock { $0.subscribers[id] = continuation }
    return stream
  }

  // MARK: - 신호 흉내

  /// 지금 구독 중인 모든 `placeChanges()` 에 캐시 쓰기 신호를 하나 보낸다.
  public func sendPlaceChange() {
    for continuation in self.state.withLock({ Array($0.subscribers.values) }) {
      continuation.yield()
    }
  }
}
