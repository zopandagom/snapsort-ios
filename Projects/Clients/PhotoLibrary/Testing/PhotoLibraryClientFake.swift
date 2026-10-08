import PhotoLibraryInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 정해 둔 값을 돌려주고, 제한 접근 선택 화면 호출을 기록한다.
/// 실제 보관함처럼 권한 요청·선택 화면 뒤에 상태가 바뀌어야 하므로 상태를 Mutex 로 보호하는 class 다.
/// 변경 알림은 실제처럼 구독마다 새 스트림을 만들고, 구독 중인 스트림에만 보낸다 (구독 전 변경은 버린다).
public final class PhotoLibraryClientFake: PhotoLibraryClient {
  public let stateAfterRequest: PhotoAccessState
  private let imageIdentifiersAfterPicker: [String]?
  private let state: Mutex<State>

  private struct State {
    var accessState: PhotoAccessState
    var imageIdentifiers: [String]
    var limitedPickerPresentCount = 0
    var nextSubscriptionID = 0
    var subscriptions: [Int: AsyncStream<Void>.Continuation] = [:]
    var changesFinished = false
  }

  /// `requestAccess()` 뒤에는 `accessState()` 도 `stateAfterRequest` 를 돌려준다.
  /// `imageIdentifiersAfterPicker` 를 주면 선택 화면이 닫힌 뒤부터 그 값을 조회 결과로 돌려주고, 실제 보관함처럼 변경 알림을 보낸다.
  public init(
    currentState: PhotoAccessState = .notDetermined,
    stateAfterRequest: PhotoAccessState = .authorized,
    imageIdentifiers: [String] = [],
    imageIdentifiersAfterPicker: [String]? = nil
  ) {
    self.stateAfterRequest = stateAfterRequest
    self.imageIdentifiersAfterPicker = imageIdentifiersAfterPicker
    self.state = Mutex(State(accessState: currentState, imageIdentifiers: imageIdentifiers))
  }

  /// 제한 접근 선택 화면을 띄운 횟수.
  public var limitedPickerPresentCount: Int {
    self.state.withLock { $0.limitedPickerPresentCount }
  }

  /// 지금 변경 알림을 구독 중인 수. 테스트가 구독이 시작된 뒤에 변경을 보내도록 기다리는 데 쓴다.
  public var imageChangesSubscriberCount: Int {
    self.state.withLock { $0.subscriptions.count }
  }

  public func accessState() -> PhotoAccessState {
    self.state.withLock { $0.accessState }
  }

  public func requestAccess() async -> PhotoAccessState {
    self.state.withLock { state in
      state.accessState = self.stateAfterRequest
      return state.accessState
    }
  }

  public func fetchImageIdentifiers() async -> [String] {
    self.state.withLock { $0.imageIdentifiers }
  }

  @MainActor
  public func presentLimitedLibraryPicker() async {
    self.state.withLock { state in
      state.limitedPickerPresentCount += 1
    }
    if let identifiers = self.imageIdentifiersAfterPicker {
      self.sendImageChange(imageIdentifiers: identifiers)
    }
  }

  public func imageChanges() async -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let id: Int? = self.state.withLock { state in
      guard !state.changesFinished else { return nil }
      let id = state.nextSubscriptionID
      state.nextSubscriptionID += 1
      state.subscriptions[id] = continuation
      return id
    }
    guard let id else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { _ = $0.subscriptions.removeValue(forKey: id) }
    }
    return stream
  }

  // MARK: - 변경 흉내

  /// 보관함이 바뀐 것처럼 조회 결과(와 권한 상태)를 바꾸고 변경 알림을 보낸다.
  public func sendImageChange(imageIdentifiers: [String], accessState: PhotoAccessState? = nil) {
    let subscriptions = self.state.withLock { state in
      state.imageIdentifiers = imageIdentifiers
      if let accessState {
        state.accessState = accessState
      }
      return Array(state.subscriptions.values)
    }
    for continuation in subscriptions {
      continuation.yield()
    }
  }

  /// 변경 알림을 끝낸다. 구독하던 쪽은 남은 알림을 처리한 뒤 반복을 마치고, 이후 구독은 바로 끝난다.
  public func finishImageChanges() {
    let subscriptions = self.state.withLock { state in
      state.changesFinished = true
      return Array(state.subscriptions.values)
    }
    for continuation in subscriptions {
      continuation.finish()
    }
  }
}
