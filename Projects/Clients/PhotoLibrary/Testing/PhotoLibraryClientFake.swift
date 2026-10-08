import PhotoLibraryInterface

/// 테스트와 Example 앱용 대역. 고정된 값을 돌려준다.
public struct PhotoLibraryClientFake: PhotoLibraryClient {
  public var currentState: PhotoAccessState
  public var stateAfterRequest: PhotoAccessState
  public var imageIdentifiers: [String]

  public init(
    currentState: PhotoAccessState = .notDetermined,
    stateAfterRequest: PhotoAccessState = .authorized,
    imageIdentifiers: [String] = []
  ) {
    self.currentState = currentState
    self.stateAfterRequest = stateAfterRequest
    self.imageIdentifiers = imageIdentifiers
  }

  public func accessState() -> PhotoAccessState {
    self.currentState
  }

  public func requestAccess() async -> PhotoAccessState {
    self.stateAfterRequest
  }

  public func fetchImageIdentifiers() async -> [String] {
    self.imageIdentifiers
  }
}
