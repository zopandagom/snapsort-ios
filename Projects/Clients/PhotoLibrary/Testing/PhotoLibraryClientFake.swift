import Core
import PhotoLibraryInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 정해 둔 값을 돌려주고, 제한 접근 선택 화면 호출을 기록한다.
/// 실제 보관함처럼 권한 요청·선택 화면 뒤에 상태가 바뀌어야 하므로 상태를 Mutex 로 보호하는 class 다.
/// 변경 알림은 실제처럼 구독마다 새 스트림을 만들고, 구독 중인 스트림에만 보낸다 (구독 전 변경은 버린다).
public final class PhotoLibraryClientFake: PhotoLibraryClient {
  public let stateAfterRequest: PhotoAccessState
  private let imageAssetsAfterPicker: [ImageAsset]?
  private let state: Mutex<State>

  private struct State {
    var accessState: PhotoAccessState
    var imageAssets: [ImageAsset]
    var limitedPickerPresentCount = 0
    var nextSubscriptionID = 0
    var subscriptions: [Int: AsyncStream<ImageChange>.Continuation] = [:]
    var changesFinished = false
  }

  /// `requestAccess()` 뒤에는 `accessState()` 도 `stateAfterRequest` 를 돌려준다.
  /// `imageAssetsAfterPicker` 를 주면 선택 화면이 닫힌 뒤부터 그 값을 조회 결과로 돌려주고, 실제 보관함처럼 달라진 만큼 증분 변경을 보낸다.
  public init(
    currentState: PhotoAccessState = .notDetermined,
    stateAfterRequest: PhotoAccessState = .authorized,
    imageAssets: [ImageAsset] = [],
    imageAssetsAfterPicker: [ImageAsset]? = nil
  ) {
    self.stateAfterRequest = stateAfterRequest
    self.imageAssetsAfterPicker = imageAssetsAfterPicker
    self.state = Mutex(State(accessState: currentState, imageAssets: imageAssets))
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

  public func fetchImageAssets() async -> [ImageAsset] {
    self.state.withLock { $0.imageAssets }
  }

  @MainActor
  public func presentLimitedLibraryPicker() async {
    self.state.withLock { state in
      state.limitedPickerPresentCount += 1
    }
    guard let assetsAfterPicker = self.imageAssetsAfterPicker else { return }
    self.send { state in
      let currentIDs = Set(state.imageAssets.map(\.id))
      let idsAfterPicker = Set(assetsAfterPicker.map(\.id))
      let inserted = assetsAfterPicker.filter { !currentIDs.contains($0.id) }
      let removed = currentIDs.subtracting(idsAfterPicker).sorted()
      state.imageAssets = assetsAfterPicker
      // 실제 보관함처럼 고른 사진이 그대로면 알리지 않는다.
      guard !inserted.isEmpty || !removed.isEmpty else { return nil }
      return .incremental(inserted: inserted, removed: removed)
    }
  }

  public func imageChanges() async -> AsyncStream<ImageChange> {
    let (stream, continuation) = AsyncStream.makeStream(of: ImageChange.self, bufferingPolicy: .unbounded)
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

  /// 이미지가 추가·삭제된 것처럼 조회 결과(와 권한 상태)를 바꾸고 증분 변경을 보낸다. 추가된 이미지는 최신순 맨 앞에 붙인다.
  /// 실제 보관함처럼 조회 결과에 이미 있는 식별자는 다시 붙이지 않는다. 보내는 변경은 받은 그대로 둔다.
  /// 추가·삭제가 모두 비면 실제 보관함처럼 알리지 않는다 (권한 상태는 바꾼다).
  public func sendIncrementalChange(
    inserted: [ImageAsset] = [],
    removed: [ImageAsset.ID] = [],
    accessState: PhotoAccessState? = nil
  ) {
    let removedIDs = Set(removed)
    self.send { state in
      let remaining = state.imageAssets.filter { !removedIDs.contains($0.id) }
      let remainingIDs = Set(remaining.map(\.id))
      state.imageAssets = inserted.filter { !remainingIDs.contains($0.id) } + remaining
      if let accessState {
        state.accessState = accessState
      }
      guard !inserted.isEmpty || !removed.isEmpty else { return nil }
      return .incremental(inserted: inserted, removed: removed)
    }
  }

  /// 무엇이 바뀌었는지 알 수 없는 변경처럼 조회 결과(와 권한 상태)를 바꾸고 전체 다시 조회를 알린다.
  public func sendReloadAll(imageAssets: [ImageAsset], accessState: PhotoAccessState? = nil) {
    self.send { state in
      state.imageAssets = imageAssets
      if let accessState {
        state.accessState = accessState
      }
      return .reloadAll
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

  // MARK: - Private

  /// 상태 변경, 보낼 변경 계산, 보내기를 한 번의 잠금 안에서 해, 구독자가 받는 순서가 상태가 바뀐 순서와 같게 한다. nil 이면 보내지 않는다.
  /// `yield` 는 `.unbounded` 버퍼라 막히지 않고 `onTermination` 도 부르지 않으므로 잠금 안에서 불러도 교착이 없다.
  private func send(_ update: (inout State) -> ImageChange?) {
    self.state.withLock { state in
      guard let change = update(&state) else { return }
      for continuation in state.subscriptions.values {
        continuation.yield(change)
      }
    }
  }
}
