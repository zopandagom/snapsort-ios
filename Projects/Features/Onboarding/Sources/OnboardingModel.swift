import Observation
import PhotoLibraryInterface

/// 사진 권한 온보딩 화면의 상태와 로직.
/// App 은 `access.canRead` 를 보고 온보딩과 보관함 화면 중 무엇을 띄울지 정한다.
/// `access` 는 한 번 정해지면 앱 실행 중 `.notDetermined` 로 돌아가지 않는다: 두 이벤트 모두 미정 값은 쓰지 않는다
/// (앱 실행 중 권한이 미정으로 돌아가는 재설치·권한 초기화는 앱을 종료해 다음 실행의 init 이 읽는다).
@MainActor
@Observable
public final class OnboardingModel {
  public private(set) var access: PhotoAccessState
  /// 권한 팝업 응답을 기다리는 중. 시작 버튼만 막는다(복귀 처리는 이 값을 보지 않는다).
  public private(set) var isRequestingAccess = false

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  /// 권한 상태는 팝업 없이 동기로 읽을 수 있으므로 init 에서 바로 읽는다.
  /// 그래야 이미 허용·거부·제한된 사용자에게 첫 프레임부터 올바른 화면이 보인다.
  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
    self.access = photoLibrary.accessState()
  }

  // MARK: - Events

  /// 권한을 아직 정하지 않았을 때만 팝업을 띄운다. 요청 중에 다시 눌러도 한 번만 요청한다(팝업이 뜨기까지 수 초 걸릴 수 있다).
  /// 결과가 미정이면(팝업이 닫힘 등) 쓰지 않는다: 요청 중 복귀로 이미 정한 값을 되돌리지 않고, 정해지지 않았으면 버튼이 다시 켜진다.
  /// 알고 둔 한계: 팝업에 답한 뒤 결과가 오기 전에 설정 앱에서 권한을 바꾸고 돌아오면, 복귀가 반영한 새 값을 늦게 온 결과가
  /// 덮을 수 있다. 드물고 다음 복귀에서 다시 읽어 맞춘다.
  public func startButtonTapped() async {
    guard self.access == .notDetermined, !self.isRequestingAccess else { return }
    self.isRequestingAccess = true
    let result = await self.photoLibrary.requestAccess()
    self.isRequestingAccess = false
    if result != .notDetermined {
      self.access = result
    }
  }

  /// 앱이 앞으로 돌아왔다(scenePhase `.active`). 설정 앱에서 권한을 바꿨을 수 있어 다시 읽는다.
  /// 미정으로 읽히면 바꾸지 않는다: 요청 중이면 팝업이 아직 떠 있을 수 있고, 허용했는데 미정으로 읽힌 적이 있다
  /// (iOS 26.5 시뮬레이터에서 `simctl privacy grant` 뒤 실측). 요청 중이어도 정해진 값이면 바로 반영해, 요청 결과가 늦거나 오지 않아도 화면이 멈추지 않는다.
  /// 요청 결과가 뒤에 오면 `startButtonTapped()` 가 그 값으로 다시 쓴다.
  public func sceneBecameActive() {
    let current = self.photoLibrary.accessState()
    guard current != .notDetermined else { return }
    self.access = current
  }
}
