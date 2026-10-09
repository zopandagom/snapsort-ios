import Core
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

  /// 개수가 아니라 식별자 집합으로 들고 있어, 처음 조회 결과와 겹치는 변경이 와도 두 번 세지 않는다.
  @ObservationIgnored private var imageIDs: Set<ImageAsset.ID> = [] {
    didSet { self.imageCount = self.imageIDs.count }
  }

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  /// 권한 상태는 동기로 읽을 수 있으므로 init 에서 읽어 첫 프레임부터 배너가 보이게 한다.
  /// App 은 온보딩 전에 이 Model 을 만들므로, 화면 진입 때도 다시 읽는다.
  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  /// 보관함 변경 구독을 먼저 시작하고 처음 불러온다. 그래야 처음 불러오는 동안 생긴 변경도 놓치지 않는다.
  /// 이후에는 바뀐 이미지만 반영하고, 무엇이 바뀌었는지 모를 때만 전체를 다시 불러온다.
  /// View 의 `.task` 수명 동안 이어지고, 화면이 사라져 Task 가 취소되면 끝난다.
  public func onAppear() async {
    let changes = await self.photoLibrary.imageChanges()
    await self.reloadImages()
    for await change in changes {
      switch change {
      case let .incremental(inserted, removed):
        self.refreshLimitedAccess()
        self.imageIDs.subtract(removed)
        self.imageIDs.formUnion(inserted.map(\.id))
      case .reloadAll:
        await self.reloadImages()
      }
    }
  }

  /// 고른 사진이 바뀌면 보관함 변경 알림이 오므로 여기서 따로 다시 불러오지 않는다.
  public func selectMorePhotosTapped() async {
    await self.photoLibrary.presentLimitedLibraryPicker()
  }

  // MARK: - Private

  /// 권한 상태도 다시 읽어, 앱 실행 중 설정에서 바뀐 제한 접근 상태를 배너에 반영한다.
  private func reloadImages() async {
    self.refreshLimitedAccess()
    self.imageIDs = await Set(self.photoLibrary.fetchImageAssets().map(\.id))
  }

  private func refreshLimitedAccess() {
    self.isLimited = self.photoLibrary.accessState() == .limited
  }
}
