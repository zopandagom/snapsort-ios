import Observation
import PhotoLibraryInterface

/// 이미지 보관함 화면의 상태와 로직.
/// 상태는 모두 private(set) 이고, View 는 이벤트 메서드 호출로만 상태 변경을 요청한다.
/// 권한 분기는 App 과 OnboardingFeature 가 맡으므로, 이 화면은 읽을 수 있는 권한이 있을 때만 뜬다.
@MainActor
@Observable
public final class LibraryModel {
  public private(set) var imageCount = 0

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
  }

  // MARK: - Events

  public func onAppear() async {
    self.imageCount = await self.photoLibrary.fetchImageIdentifiers().count
  }
}
