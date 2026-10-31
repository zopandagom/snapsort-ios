/// 앱이 뒤에 있거나 닫혀 있을 때의 분류 (docs/ARCHITECTURE.md §4 인덱싱). 다른 Client(Indexing·TripPlace·WidgetTimeline)를 조합한다.
/// 앱이 뒤로 가면 진행 중 저장이 끝날 때까지 실행 시간을 빌려 앞 실행을 멈추고 BG 처리 요청(충전 중)을 제출한다.
/// BG 작업이 도는 중이면 그 작업이 실행을 쥐고 완료 전에 저장소에서 손 떼고 필요하면 다시 예약하므로, 빌리지도 제출하지도 않는다.
/// 시스템이 그 요청을 실행하면 분류를 이어 하고 1단계를 마친 뒤 여행 장소 이름 미리 받기 회차를 한 번 돌린다.
/// 사용자가 시작한 계속 처리 분류(`BGContinuedProcessingTask`)는 앱이 앞에 있을 때 요청하고, 시스템 진행 화면에 개수를 보이며
/// 분류·글자 읽기를 마치고 함께 돌던 미리 받기 회차가 끝나면 완료한다. 바로 시작하지 못하면 위 흐름(뒤로 갈 때 멈춤 + BG 처리 요청)이 그대로 돈다.
/// 구현은 BackgroundIndexingImpl, 테스트 대역은 BackgroundIndexingTesting 에 있다.
public protocol BackgroundIndexingClient: Sendable {
  /// 앱이 뒤로 갔다(scenePhase `.background`, 화면이 처음 생길 때의 값 포함). 진행 중 저장이 끝날 때까지 실행 시간을 빌려 분류와
  /// 미리 받기의 저장소 출입을 멈추고, 인덱서가 있으면 BG 처리 요청을 제출한다. BG 작업(처리·계속 처리)이 도는 중이면 빌리지도 제출하지도 않고
  /// 저장소 출입만 맞춘다(그 작업이 쥔다). 이미 뒤에 있으면 아무것도 하지 않는다.
  @MainActor func appDidEnterBackground()
  /// 앱이 앞으로 왔다(scenePhase `.active`. 앞에서 켤 때 처음 값은 `.inactive` 이고 `.active` 는 변화로 온다). 멈춘 분류와 미리 받기 저장소 출입을 다시 연다.
  /// 이미 앞에 있으면 아무것도 하지 않는다.
  @MainActor func appDidBecomeActive()
  /// 계속 처리 분류 상태. 바뀜을 알리지 않으므로 받는 쪽이 필요할 때 읽는다(진행률을 받을 때·앱이 앞으로 올 때·요청 뒤).
  @MainActor var continuedIndexingState: ContinuedIndexingState { get }
  /// 사용자가 시작한 계속 처리 분류를 요청한다. 앱이 앞에 있을 때만 제출한다. 이미 도는 중이면 다시 제출하지 않고 `.started` 다.
  /// `text` 는 시스템 진행 화면 문구를 만든다(개수와 고정 문구만).
  @MainActor func requestContinuedIndexing(text: ContinuedIndexingText) -> ContinuedIndexingRequestResult
}

/// 사용자가 시작한 계속 처리 분류(`BGContinuedProcessingTask`)의 상태.
public enum ContinuedIndexingState: Sendable, Equatable {
  /// 이 기기·실행에서 쓸 수 없다(식별자·등록·저장소 없음, 제출이 영구 실패).
  case unsupported
  /// 요청할 수 있다.
  case idle
  /// 제출했고 아직 끝나지 않았다(핸들러 대기·실행·마무리 포함).
  case active
}

/// 시스템 진행 화면에 보일 단계와 수. 개수만 담는다(사진·텍스트·장소 없음).
public struct ContinuedIndexingStatus: Sendable, Equatable {
  public enum Stage: Sendable, Equatable {
    /// 제출 때. 수는 0 이다.
    case preparing
    /// 1단계 분류. 수는 보관함 화면 진행 카드와 같다(분류·건너뜀 / 전체).
    case classifying
    /// 2단계 글자 읽기. 식은 진행 카드와 같다(이번 실행 처리 / 처리 + 대기). 배치 안에서는 장마다 저장 전 값을 받아 카드보다 최대 한 배치 앞설 수 있다.
    case recognizingText
    /// 분류·글자 읽기를 마친 뒤 함께 돌던 여행 장소 이름 미리 받기 회차. 수는 그 회차의 키 수(회차가 아직 알리지 않았으면 0·0).
    case fetchingPlaceNames
  }

  public let stage: Stage
  /// 그 단계에서 처리한 수.
  public let doneCount: Int
  /// 그 단계의 전체 수.
  public let totalCount: Int

  public init(stage: Stage, doneCount: Int, totalCount: Int) {
    self.stage = stage
    self.doneCount = doneCount
    self.totalCount = totalCount
  }
}

/// 시스템 진행 화면 문구를 만드는 쪽(Feature)이 넘긴다. 개수와 고정 문구만 쓴다.
public struct ContinuedIndexingText: Sendable {
  public let title: @Sendable (ContinuedIndexingStatus) -> String
  public let subtitle: @Sendable (ContinuedIndexingStatus) -> String

  public init(
    title: @escaping @Sendable (ContinuedIndexingStatus) -> String,
    subtitle: @escaping @Sendable (ContinuedIndexingStatus) -> String
  ) {
    self.title = title
    self.subtitle = subtitle
  }
}

/// 계속 처리 분류 요청 결과.
public enum ContinuedIndexingRequestResult: Sendable, Equatable {
  /// 제출했거나 이미 도는 중이다.
  case started
  /// 지금은 못 한다(앱이 앞이 아님, 시스템이 바로 돌릴 수 없음, 요청 수 초과). 나중에 다시 요청할 수 있다.
  case temporarilyUnavailable
  /// 이 실행에서는 못 한다. 상태가 `.unsupported` 가 된다.
  case unavailable
}
