import PhotoLibraryInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 정해 둔 값을 돌려주고, 제한 접근 선택 화면 호출을 기록한다.
/// 실제 보관함처럼 권한 요청·선택 화면 뒤에 상태가 바뀌어야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class PhotoLibraryClientFake: PhotoLibraryClient {
  public let stateAfterRequest: PhotoAccessState
  private let imageIdentifiersAfterPicker: [String]?
  private let state: Mutex<State>

  private struct State {
    var accessState: PhotoAccessState
    var imageIdentifiers: [String]
    var limitedPickerPresentCount = 0
  }

  /// `requestAccess()` 뒤에는 `accessState()` 도 `stateAfterRequest` 를 돌려준다.
  /// `imageIdentifiersAfterPicker` 를 주면 선택 화면이 닫힌 뒤부터 그 값을 조회 결과로 돌려준다.
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
      if let identifiers = self.imageIdentifiersAfterPicker {
        state.imageIdentifiers = identifiers
      }
    }
  }
}
