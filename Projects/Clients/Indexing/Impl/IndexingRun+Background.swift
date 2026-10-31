import IndexingInterface

/// BG 모드에서만 다른 인덱서 동작 (docs/ARCHITECTURE.md §4 인덱싱).
/// 앱이 비활성이고 BG 작업이 실행을 쥐면 BG 모드다. 모드는 부를 때마다 실행기에서 읽어 앞(활성)이 우선한다.
/// - 1단계 바코드 확인 실패: 바코드 없음으로 저장하지 않고 그 장을 이번 실행에서 미룬다(IndexingRun+Barcode.swift).
/// - 이미지 분석이 분류할 수 없으면(`isClassificationAvailable`. 앞에서 불러 둔 요청이 없거나, 세션이 없고 시한을 넘기고 돌아오지 않은 작업이 둘 이상이라 그것이 돌아올 때까지 멈춤)
///   남은 1단계 대상을 저장하지 않고 이번 실행에서 미룬다(IndexingRun+Stages.swift, 이 미룸은 앞 실행에서도 같다). 다시 예약 사유는 아니다
///   (앞에서 다음 실행이 분류한다).
/// - 분류 보강이 거부(`.rejected`, 속도 제한 포함)되거나 모델 차단 중이면 규칙 결과로 저장하지 않고 그 장을 대기로 남긴다(IndexingRun+ModelFill.swift).
/// - 분류·OCR·바코드 Vision 요청이 잇달아 실패하면 실행을 멈춘다(`.visionStopped`). 이미지 읽기 실패와 특징 벡터 실패는 세지 않는다
///   (벡터는 선택 기능이라 분류·OCR 을 멈출 근거가 아니다. 벡터는 실행 안 연속 실패 차단만 따른다).
/// - 처음 비교에서 사진 조회가 비었는데 저장된 결과가 있으면 지우지 않고 멈춘다(`.libraryEmpty`, 잠긴 기기에서 읽지 못했을 수 있다).
/// - 배치 경계(본 루프 맨 위·1단계 저장 직후)에서 양보(`shouldYield`, 발열)를 본다.
/// 특징 벡터는 BG 모드에서도 같게 요청한다(뒤에서는 이미지 분석이 앞에서 불러 둔 요청으로만 만들고 뒤 시한 차단을 따른다).
extension IndexingRun {
  /// BG 모드에서 분류·OCR·바코드 Vision 요청이 이 수만큼 잇달아 실패하면 실행을 멈춘다. 임시 값이다.
  static let maxConsecutiveBackgroundVisionFailures = 3

  /// 지금 BG 모드인지. 부를 때마다 실행기 상태를 읽는다(앞이 우선).
  var isBackgroundMode: Bool {
    self.environment.isBackground()
  }

  /// 분류·OCR·바코드 Vision 요청의 성공·실패를 센다. 실패는 BG 모드에서만 센다(앞 모드는 지금처럼 그 장만 미룬다).
  mutating func recordVisionResult(succeeded: Bool) {
    guard !succeeded else {
      self.consecutiveVisionFailures = 0
      return
    }
    self.environment.record(.visionFailure)
    if self.isBackgroundMode {
      self.consecutiveVisionFailures += 1
    }
  }

  /// BG 모드에서 Vision 이 잇달아 실패해 실행을 멈춰야 하는지.
  var shouldStopForVisionFailures: Bool {
    self.isBackgroundMode && self.consecutiveVisionFailures >= Self.maxConsecutiveBackgroundVisionFailures
  }

  /// 배치 경계에서 부른다. BG 모드이고 양보해야 하면(발열) 멈춘다. 그 배치의 저장은 부르는 쪽이 이미 마쳤다.
  func yieldIfNeeded() throws(IndexingStop) {
    if self.isBackgroundMode, self.environment.shouldYield() {
      throw .yielded
    }
  }
}

/// 실행이 실행기에서 읽는 값과 알리는 곳. 기본값은 "앞 모드, 양보 안 함, 알림 없음"이라 테스트의 `makeRun()` 이 지금처럼 돈다.
struct RunEnvironment: Sendable {
  /// 지금 BG 모드인지. 부를 때마다 실행기 상태를 읽는다.
  var isBackground: @Sendable () -> Bool = { false }
  /// BG 모드에서 배치 경계마다 본다.
  var shouldYield: @Sendable () -> Bool = { false }
  /// 변경을 기다리기 직전(할 일이 없어졌다).
  var onIdle: @Sendable () -> Void = {}
  /// BG 수치·미룸 기록.
  var record: @Sendable (BackgroundRunEvent) -> Void = { _ in }
  /// 2단계 배치 안 장마다의 저장 전 진행률. BG hold 에만 간다(앞 구독자·최신 값·보관 값에는 넣지 않는다. 계속 처리 작업의 진행 간격을 좁힌다).
  var reportToHolds: @Sendable (IndexingProgress) -> Void = { _ in }
}

/// 실행이 실행기에 알리는 일. 실행기가 BG 가 쥔 동안의 수를 세고(Debug 수치 로그) 미룸이 있었는지 본다.
/// 정수로만 센다. 식별자·텍스트를 담지 않는다 (docs/CONVENTIONS.md §4).
enum BackgroundRunEvent: Sendable {
  /// 1단계에서 저장한 장 수.
  case classified(Int)
  /// 2단계에서 글자를 읽어 저장한 장 수.
  case recognized(Int)
  /// BG 모드에서 바코드 확인 실패로 미뤘다.
  case barcodeDeferred
  /// BG 모드에서 분류 보강 거부·모델 차단으로 대기로 남겼다.
  case modelDeferred
  /// 모델이 거부했다(모드와 관계없이).
  case modelRejected
  /// 분류·OCR·바코드 Vision 요청이 실패했다(모드와 관계없이).
  case visionFailure
  /// 특징 벡터를 만들었다.
  case featurePrint
  /// 특징 벡터 요청이 실패했다.
  case featurePrintFailure
  /// 이미지 분석이 분류할 수 없어 1단계에서 미룬 장 수.
  case classificationHeld(Int)
}

/// BG 가 쥔 동안의 수 (Debug 수치 로그).
struct BackgroundRunStats: Sendable, Equatable {
  var classified = 0
  var recognized = 0
  var barcodeDeferred = 0
  var modelDeferred = 0
  var modelRejected = 0
  var visionFailures = 0
  var featurePrints = 0
  var featurePrintFailures = 0
  var classificationHeld = 0

  /// 다시 예약할 미룸이 있었는지. 벡터 대기는 넣지 않는다(뒤 차단은 프로세스 끝까지라 같은 프로세스에서 다시 예약해도 못 만든다).
  /// 분류 미룸도 넣지 않는다(뒤에서는 분류 요청을 새로 불러오지 않아 다시 떠도 같은 일을 되풀이한다. 앞에서 다음 실행이 분류한다).
  var hasDeferred: Bool {
    self.barcodeDeferred > 0 || self.modelDeferred > 0
  }

  mutating func add(_ event: BackgroundRunEvent) {
    switch event {
    case let .classified(count): self.classified += count
    case let .recognized(count): self.recognized += count
    case .barcodeDeferred: self.barcodeDeferred += 1
    case .modelDeferred: self.modelDeferred += 1
    case .modelRejected: self.modelRejected += 1
    case .visionFailure: self.visionFailures += 1
    case .featurePrint: self.featurePrints += 1
    case .featurePrintFailure: self.featurePrintFailures += 1
    case let .classificationHeld(count): self.classificationHeld += count
    }
  }
}

/// 실행(`IndexingRun.start`)이 끝난 이유.
enum IndexingRunEnd: String, Sendable {
  /// Task 취소 또는 닫힌 저장소 문.
  case cancelled
  case storeFailed
  case notReadable
  /// BG 모드에서 양보했다(발열).
  case yielded
  /// BG 모드에서 Vision 이 잇달아 실패했다.
  case visionStopped
  /// BG 모드에서 사진 조회가 비었는데 저장된 결과가 있다.
  case libraryEmpty
  /// 보관함 변경 스트림이 끝나 남은 일을 마쳤다.
  case changesEnded

  init(_ stop: IndexingStop) {
    switch stop {
    case .cancelled: self = .cancelled
    case .storeFailed: self = .storeFailed
    case .notReadable: self = .notReadable
    case .yielded: self = .yielded
    case .visionStopped: self = .visionStopped
    case .libraryEmpty: self = .libraryEmpty
    }
  }

  /// BG 가 다시 예약할 일이 남는지.
  var leavesRemainingWork: Bool {
    switch self {
    case .cancelled, .storeFailed, .yielded, .visionStopped, .libraryEmpty: true
    case .notReadable, .changesEnded: false
    }
  }
}
