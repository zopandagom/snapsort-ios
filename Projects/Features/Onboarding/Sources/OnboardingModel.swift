import Observation
import PhotoLibraryInterface

/// 사진 권한 온보딩 화면의 상태와 로직.
/// App 은 `access.canRead` 를 보고 온보딩과 보관함 화면 중 무엇을 띄울지 정한다.
@MainActor
@Observable
public final class OnboardingModel {
  public private(set) var access: PhotoAccessState

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  /// 권한 상태는 팝업 없이 동기로 읽을 수 있으므로 init 에서 바로 읽는다.
  /// 그래야 이미 허용·거부한 사용자에게 첫 프레임부터 올바른 화면이 보인다.
  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
    self.access = photoLibrary.accessState()
  }

  // MARK: - Events

  public func startButtonTapped() async {
    self.access = await self.photoLibrary.requestAccess()
  }
}
