import Observation
import PhotoLibraryInterface

/// 스크린샷 보관함 화면의 상태와 로직.
/// 상태는 모두 private(set) 이고, View 는 이벤트 메서드 호출로만 상태 변경을 요청한다.
@MainActor
@Observable
public final class LibraryModel {
  public private(set) var access: PhotoAccessState = .notDetermined
  public private(set) var screenshotCount = 0

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
  }

  // MARK: - Events

  public func onAppear() async {
    self.access = self.photoLibrary.accessState()
    await self.reloadScreenshots()
  }

  public func startButtonTapped() async {
    self.access = await self.photoLibrary.requestAccess()
    await self.reloadScreenshots()
  }

  // MARK: - Private

  private func reloadScreenshots() async {
    guard self.access.canRead else {
      self.screenshotCount = 0
      return
    }
    self.screenshotCount = await self.photoLibrary.fetchScreenshotIdentifiers().count
  }
}
