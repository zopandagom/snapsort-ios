import Observation
import PhotoLibraryInterface

/// 이미지 보관함 화면의 상태와 로직.
/// 상태는 모두 private(set) 이고, View 는 이벤트 메서드 호출로만 상태 변경을 요청한다.
/// 권한 분기는 App 과 OnboardingFeature 가 맡으므로, 이 화면은 읽을 수 있는 권한이 있을 때만 뜬다.
@MainActor
@Observable
public final class LibraryModel {
  public private(set) var imageCount = 0
  /// 사용자가 고른 사진만 읽을 수 있는 제한 접근 상태인지. 화면에 안내 배너를 띄우는 데 쓴다.
  public private(set) var isLimited: Bool

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  /// 권한 상태는 동기로 읽을 수 있으므로 init 에서 읽어 첫 프레임부터 배너가 보이게 한다.
  /// App 은 온보딩 전에 이 Model 을 만들므로, 화면 진입 때도 다시 읽는다.
  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  public func onAppear() async {
    await self.reloadImages()
  }

  public func selectMorePhotosTapped() async {
    await self.photoLibrary.presentLimitedLibraryPicker()
    await self.reloadImages()
  }

  // MARK: - Private

  private func reloadImages() async {
    self.isLimited = self.photoLibrary.accessState() == .limited
    self.imageCount = await self.photoLibrary.fetchImageIdentifiers().count
  }
}
