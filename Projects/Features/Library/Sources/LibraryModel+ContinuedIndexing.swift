import BackgroundIndexingInterface
import IndexingInterface
import Observation
import PhotoLibraryInterface

/// 계속 처리 분류(`BackgroundIndexingClient.requestContinuedIndexing`)를 요청했는데 시작하지 못했을 때 진행 카드에 보일 안내.
/// 사용자가 버튼으로 요청했을 때만 둔다(첫 분류 자동 요청의 실패는 조용히 지나간다).
public enum ContinuedIndexingNotice: Sendable, Equatable {
  /// 지금은 시작할 수 없다(시스템이 바로 돌릴 수 없음 등). 다시 누를 수 있다.
  case tryLater
  /// 이 실행에서는 쓸 수 없다. 버튼이 사라지고 지금 흐름(앱이 뒤로 가면 멈춤, 충전 중 BG 작업)으로 분류한다.
  case unavailable
}

public extension LibraryModel {
  /// 계속 처리 분류 상태. `.idle` 일 때만 진행 카드 버튼을 보인다.
  var continuedIndexingState: ContinuedIndexingState {
    self.backgroundIndexing.continuedState
  }

  /// 버튼으로 요청했는데 시작하지 못했을 때의 안내. 다음 탭에 지운다. "잠시 뒤 다시"(`.tryLater`)는 앱이 앞으로 오거나
  /// 분류·글자 읽기가 끝나도 지운다(누르지 않은 다음 카드에 남지 않게). 쓸 수 없음(`.unavailable`)은 이 실행 동안 둔다.
  var continuedIndexingNotice: ContinuedIndexingNotice? {
    self.backgroundIndexing.notice
  }

  /// 진행 카드의 "홈으로 나가도 계속" 버튼을 보일지: 계속 처리 분류를 요청할 수 있고, 분류나 글자 읽기가 돌고 있다(멈춤·다 함은 아님).
  var showsContinueInBackgroundButton: Bool {
    guard self.continuedIndexingState == .idle, self.isIndexing, !self.isIndexingStopped,
          let progress = self.indexingProgress
    else { return false }
    return !progress.isFinished
  }

  /// 진행 카드의 "홈으로 나가도 계속"을 눌렀다. 계속 처리 분류를 요청한다(앱이 앞에 있고 버튼이 보일 때만).
  /// 시작하면 버튼이 사라지고, 시작하지 못하면 안내를 둔다(이 실행에서 쓸 수 없으면 버튼도 사라진다).
  func continueInBackgroundTapped() {
    guard self.showsContinueInBackgroundButton, self.isSceneActive else { return }
    self.backgroundIndexing.requestTapped()
  }

  /// 시스템 진행 화면(잠금 화면·다이내믹 아일랜드)의 제목과 부제. 개수와 고정 문구만 담는다(사진·텍스트·장소 없음).
  /// 제목은 보관함 진행 카드의 문구와 같다. 장소 이름 단계는 카드에 대응이 없다(카드는 장소 받기를 보이지 않는다).
  static let continuedIndexingText = ContinuedIndexingText(
    title: { status in
      switch status.stage {
      case .preparing: "이미지 분류 준비 중"
      case .classifying: "이미지 분류 중"
      case .recognizingText: "글자 읽는 중"
      case .fetchingPlaceNames: "장소 이름 받는 중"
      }
    },
    subtitle: { status in
      switch status.stage {
      case .preparing:
        "홈으로 나가도 이어서 분류합니다"
      case .classifying, .recognizingText:
        "\(status.doneCount)/\(status.totalCount)장"
      case .fetchingPlaceNames:
        // 회차가 물을 키를 정하기 전(앞 회차가 남긴 요청 기다림 등)에는 수가 없다.
        status.totalCount > 0 ? "\(status.doneCount)/\(status.totalCount)곳" : "잠시만 기다려 주세요"
      }
    }
  )
}

/// 보관함 화면과 `BackgroundIndexingClient` 사이(docs/ARCHITECTURE.md §4 인덱싱): 앱이 뒤로 가고 앞으로 올 때 알리고, 계속 처리 분류의 상태를 읽고 요청한다.
/// `LibraryModel` 이 소유한다. 이 파일로 나눈 것은 LibraryModel 파일 길이 때문이다.
/// Client 가 없으면 알리지 않고 상태는 `.unsupported` 다(Example 은 Fake 를 넘겨 버튼·안내를 본다).
/// 첫 분류는 자동으로 요청한다: LibraryModel 을 만들 때 사진 권한이 미정이었고(이번 실행에서 온보딩 "시작"으로 권한을 받음),
/// 이번 실행에서 처음 받은 진행률이 끝나지 않았고 그때 앱이 앞에 있다. 그 뒤로는 사용자가 진행 카드 버튼을 눌러야 요청한다
/// (App Review "사용자가 시작한 작업". 앱이 뒤로 갈 때는 요청하지 않는다).
/// 상태는 Client 가 바뀜을 알리지 않으므로 요청 뒤·진행률마다·앱이 앞으로 올 때 다시 읽는다.
@MainActor
@Observable
final class LibraryBackgroundIndexing {
  private(set) var continuedState: ContinuedIndexingState
  private(set) var notice: ContinuedIndexingNotice?

  /// 첫 분류 자동 요청을 아직 할 수 있는지. 한 번 꺼지면 이 실행 동안 다시 켜지지 않는다(화면을 다시 들어와도).
  @ObservationIgnored private var isAutoRequestPending: Bool
  @ObservationIgnored private let client: (any BackgroundIndexingClient)?

  /// - Parameter access: LibraryModel 을 만들 때의 사진 권한. App 은 온보딩 전에 LibraryModel 을 만드므로, 미정이면 이번 실행에서
  ///   온보딩 "시작"으로 권한을 받는다는 뜻이다. 그때만 첫 분류를 자동 요청한다.
  init(client: (any BackgroundIndexingClient)?, access: PhotoAccessState) {
    self.client = client
    self.continuedState = client?.continuedIndexingState ?? .unsupported
    self.isAutoRequestPending = access == .notDetermined
  }

  /// 분류 진행률을 받았다. 첫 진행률이 끝나지 않았고 앱이 앞이면 자동 요청한다(결과는 상태로만, 안내 없음).
  /// 끝난 진행률(0장·이미 다 함)이면 요청하지 않고 자동 요청을 끝낸다. 앱이 앞이 아니면 다음 진행률까지 미룬다.
  /// 끝난 진행률이면 "잠시 뒤 다시" 안내도 지운다.
  func indexingProgressChanged(_ progress: IndexingProgress, isSceneActive: Bool) {
    if progress.isFinished {
      self.clearTryLater()
    }
    if self.isAutoRequestPending, progress.isFinished {
      self.isAutoRequestPending = false
    } else if self.isAutoRequestPending, isSceneActive {
      self.isAutoRequestPending = false
      _ = self.client?.requestContinuedIndexing(text: LibraryModel.continuedIndexingText)
    }
    self.refreshState()
  }

  /// 사용자가 버튼을 눌렀다. 보일 조건은 LibraryModel 이 확인한다.
  func requestTapped() {
    guard let client = self.client else { return }
    self.notice = nil
    let result = client.requestContinuedIndexing(text: LibraryModel.continuedIndexingText)
    self.refreshState()
    switch result {
    case .started:
      break
    case .temporarilyUnavailable:
      self.notice = .tryLater
    case .unavailable:
      self.notice = .unavailable
    }
  }

  /// 앱이 앞으로 왔다. Client 에 알린 뒤, 그사이 끝났거나 시작하지 못한 요청이 풀렸을 수 있어 상태를 다시 읽고 "잠시 뒤 다시" 안내를 지운다.
  func sceneBecameActive() {
    self.client?.appDidBecomeActive()
    self.clearTryLater()
    self.refreshState()
  }

  /// 앱이 뒤로 갔다. Client 에 알린다(분류를 멈춰 BG 작업에 넘기거나, 계속 처리 분류가 쥐고 있으면 이어 간다).
  /// 첫 진행률 전에 떠났으면 돌아왔을 때 시스템 진행 표시가 갑자기 뜨지 않게 첫 분류 자동 요청을 끝낸다.
  func sceneEnteredBackground() {
    self.isAutoRequestPending = false
    self.client?.appDidEnterBackground()
  }

  private func clearTryLater() {
    if self.notice == .tryLater {
      self.notice = nil
    }
  }

  private func refreshState() {
    let state = self.client?.continuedIndexingState ?? .unsupported
    // 진행률마다 다시 읽으므로, 같으면 대입하지 않아 카드를 다시 그리지 않는다.
    if self.continuedState != state {
      self.continuedState = state
    }
  }
}
