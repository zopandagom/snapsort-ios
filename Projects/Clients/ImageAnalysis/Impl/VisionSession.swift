import Core
import Foundation
import ImageAnalysisInterface
import Synchronization
import Vision
#if DEBUG
  import os
#endif

/// 앞에서 처음 성공한 분류·특징 벡터 요청과 그것을 돌린 순서 핸들러 (docs/ARCHITECTURE.md §4 인덱싱).
/// 뒤에서는 분류 모델을 새로 불러오지 못할 수 있어(실기기) 앞에서 불러 둔 이 요청으로만 분류·벡터를 만든다.
/// 이미지마다 `VNImageRequestHandler` 를 새로 만들지 않고 핸들러 하나를 계속 쓴다(핸들러가 쥔 상태를 뒤에서 새로 만들지 않는다).
/// 요청·핸들러는 동시에 쓸 수 없어 직렬 큐 하나에서만 만진다. Vision 이 동기라 협력 스레드를 막지 않게 큐에서 돈다.
final class VisionSession: Sendable {
  /// 세션이 쥔 요청 종류. Debug 로그의 `kind=` 와 같은 이름이다.
  enum Kind: String, Sendable {
    case classify
    case featurePrint
  }

  /// 세션이 쥔 Vision 객체. 동시에 쓸 수 없어 `objects` 잠금 안(큐 작업 안)에서만 쓴다.
  struct Objects {
    let handler: VNSequenceRequestHandler
    let classify: VNClassifyImageRequest
    let featurePrint: VNGenerateImageFeaturePrintRequest
  }

  /// 한 작업의 시한(임시 값). 큐에서 작업이 시작할 때부터 센다(앞 작업을 기다린 시간은 세지 않는다). 분류·벡터가 같이 쓴다.
  /// 분류·벡터는 같은 모델·같은 썸네일 입력·같은 큐다. iOS 27 시뮬레이터 GPU 에서 벡터 요청이 10분 넘게 돌아오지 않은 실측이 있어 둔다.
  /// 시뮬레이터 CPU 분류 375~426ms·벡터 72ms(첫 호출 0.29s), Mac 벡터 4.8ms/장. 실기기 분류 시간·뒤(낮은 우선순위·발열)의 시간은 확인 못 했다.
  /// 넘기면 그 큐를 버리고(`VisionWorkQueue`) 세대를 버린다(`VisionSessions.timedOut`). 벡터는 앞·뒤 차단도 건다(`FeaturePrintAvailability`).
  static let timeout: Duration = .seconds(5)
  /// 세대에서 그 종류의 첫 작업(모델을 불러온다)의 시한(임시 값). 적재 시간 실측이 없어, 적재가 5초를 넘는 기기에서 세대마다 첫 장이
  /// 걸려 버리고 다시 만드는 일이 되풀이되지 않게 적재 한 번을 넉넉히 덮는 값으로 잡는다. 실기기 기록 도구의 첫 장 `classifyMs` 와 비교한다.
  static let firstUseTimeout: Duration = .seconds(20)

  private let work = VisionWorkQueue(label: "com.zopandagom.snapsort.vision-session")
  /// 큐 안에서만 잠그므로 늘 경합이 없다. Sendable 이 아닌 Vision 객체를 담는 용도다.
  private let objects: Mutex<Objects>

  /// 요청 객체만 만든다. 모델은 첫 perform 때 불러온다.
  init() {
    self.objects = Mutex(Self.makeObjects())
  }

  /// 요청 설정. 분류는 revision 2(새 API `ClassifyImageRequest` 와 같은 판), 벡터는 `FeaturePrinting.revision` 과 기본
  /// 자르기(`.scaleFill`)다.
  /// SDK 가 바뀌면 기본 revision 이 바뀔 수 있어 명시한다. 장치는 지정하지 않는다(기본 장치).
  static func makeObjects() -> Objects {
    let classify = VNClassifyImageRequest()
    classify.revision = VNClassifyImageRequestRevision2
    let featurePrint = VNGenerateImageFeaturePrintRequest()
    featurePrint.revision = FeaturePrinting.revision
    featurePrint.imageCropAndScaleOption = .scaleFill
    return Objects(handler: VNSequenceRequestHandler(), classify: classify, featurePrint: featurePrint)
  }

  /// 모든 라벨을 돌려준다(걸러 내기·정렬은 부르는 쪽 `ImageClassification`). 결과가 없으면 빈 배열이다.
  /// `timeout`·`hooks` 는 큐에 넘긴다(`VisionWorkQueue.run`).
  func classify(
    _ image: AnalysisImage,
    timeout: Duration,
    hooks: VisionWorkQueue.Hooks
  ) async throws -> [ImageLabel] {
    try await self.work.run(timeout: timeout, hooks: hooks) {
      try self.objects.withLock { objects in
        try objects.handler.perform([objects.classify], on: image.cgImage, orientation: image.orientation)
        return (objects.classify.results ?? []).map { observation in
          ImageLabel(identifier: observation.identifier, confidence: observation.confidence)
        }
      }
    }
  }

  /// 특징 벡터를 만든다. 결과가 없거나 저장 형식으로 바꿀 수 없으면 `ImageAnalysisError.failed` 를 던진다.
  /// `timeout`·`hooks` 는 큐에 넘긴다(`VisionWorkQueue.run`).
  func featurePrint(
    _ image: AnalysisImage,
    timeout: Duration,
    hooks: VisionWorkQueue.Hooks
  ) async throws -> ImageFeaturePrint {
    try await self.work.run(timeout: timeout, hooks: hooks) {
      try self.objects.withLock { objects in
        try objects.handler.perform([objects.featurePrint], on: image.cgImage, orientation: image.orientation)
        guard let result = objects.featurePrint.results?.first else {
          throw ImageAnalysisError.failed
        }
        let observation = FeaturePrintObservation(result)
        guard let featurePrint = FeaturePrinting.featurePrint(
          data: observation.data,
          elementType: observation.elementType,
          elementCount: observation.elementCount
        ) else {
          throw ImageAnalysisError.failed
        }
        return featurePrint
      }
    }
  }
}

/// 프로세스가 쥔 세션 자리의 판정 (docs/ARCHITECTURE.md §4 인덱싱). 앞에서는 없으면 새 세대로 만들고, 뒤에서는 만들지 않고
/// 이 세대에서 그 종류가 성공한 적 있을 때만 쓴다. 실패·시한 초과면 그 세대를 버린다. 옛 세대의 늦은 결과는 무시한다.
/// 시한으로 버린 큐 중 작업이 아직 돌아오지 않은 수(`stuckQueues`)가 상한에 닿으면 앞에서도 새로 만들지 않는다
/// (버린 큐마다 돌아오지 않는 Vision 작업이 스레드 하나를 쥔다).
/// 순수 값 타입이라 테스트가 프로세스 전역(`VisionSessions`)을 바꾸지 않고 판정을 본다.
struct VisionSessionSlot: Sendable, Equatable {
  enum Checkout: Equatable {
    /// 쥔 세대를 쓴다. `isFirstUse` 는 이 세대에서 그 종류가 아직 성공한 적 없는지다(모델을 불러온다).
    case use(Int, isFirstUse: Bool)
    /// 이 세대로 새로 만든다(늘 첫 사용).
    case create(Int)
    /// 쓸 수 없다(Vision 을 부르지 않는다).
    case unavailable
  }

  /// 돌아오지 않은 버린 큐 수의 상한(임시 값). 첫 시한 초과는 무거운 순간의 첫 적재일 수 있어 한 번은 새로 만들어 본다.
  static let maxStuckQueues = 2

  /// 쥔 세션의 세대. nil 이면 없다.
  private(set) var generation: Int?
  /// 이 세대에서 성공한 적 있는 종류.
  private(set) var warmed: Set<VisionSession.Kind> = []
  /// 시한으로 버린 큐 중 작업이 아직 돌아오지 않은 수.
  private(set) var stuckQueues = 0
  private var nextGeneration = 1

  /// 새 세션을 만들 수 있는지(돌아오지 않은 버린 큐가 상한 아래).
  var canCreate: Bool {
    self.stuckQueues < Self.maxStuckQueues
  }

  /// 세션이 있으면 앞이거나 그 종류가 준비됐을 때, 없으면 앞이고 새로 만들 수 있을 때 true 다.
  func isAvailable(_ kind: VisionSession.Kind, isAppActive: Bool) -> Bool {
    if self.generation != nil {
      return isAppActive || self.warmed.contains(kind)
    }
    return isAppActive && self.canCreate
  }

  mutating func checkout(_ kind: VisionSession.Kind, isAppActive: Bool) -> Checkout {
    if let generation {
      let isWarmed = self.warmed.contains(kind)
      return isAppActive || isWarmed ? .use(generation, isFirstUse: !isWarmed) : .unavailable
    }
    guard isAppActive, self.canCreate else {
      return .unavailable
    }
    let generation = self.nextGeneration
    self.nextGeneration += 1
    self.generation = generation
    self.warmed = []
    return .create(generation)
  }

  /// 그 세대면 그 종류를 준비됨으로 둔다. 이 세대에서 처음이면 true(준비 로그).
  mutating func succeeded(_ kind: VisionSession.Kind, generation: Int) -> Bool {
    guard generation == self.generation else {
      return false
    }
    return self.warmed.insert(kind).inserted
  }

  /// 그 세대면 비우고 true(버림 로그). 옛 세대는 무시한다. 돌아오지 않은 큐 수는 바꾸지 않는다(실패한 작업은 돌아왔다).
  mutating func discard(generation: Int) -> Bool {
    guard generation == self.generation else {
      return false
    }
    self.generation = nil
    self.warmed = []
    return true
  }

  /// 그 세대의 큐가 시한을 넘겼다. 세대와 관계없이 돌아오지 않은 큐로 세고(옛 세대 큐도 스레드를 쥔다), 그 세대면 비운다.
  /// `reachedLimit` 은 지금 상한에 닿아 있는지다(닿을 때마다 로그).
  mutating func timedOut(generation: Int) -> (discarded: Bool, reachedLimit: Bool) {
    self.stuckQueues += 1
    let discarded = self.discard(generation: generation)
    return (discarded, !self.canCreate)
  }

  /// 시한으로 버린 큐의 작업이 늦게 돌아왔다. 0 아래로 내려가지 않는다.
  mutating func stuckQueueReturned() {
    self.stuckQueues = max(self.stuckQueues - 1, 0)
  }
}

/// 프로세스에 하나인 세션 자리. 같은 프로세스의 모든 `ImageAnalysisClientImpl` 값이 같이 쓴다.
/// 앱 활성 값은 `FeaturePrinting.availability` 하나가 원천이다. 부르는 쪽이 그 값을 읽고 놓은 뒤 넘긴다(두 잠금을 겹쳐 쥐지 않는다).
/// 테스트는 이 값을 바꾸지 않는다. 판정은 `VisionSessionSlot`, 차례·취소·시한은 `VisionWorkQueue` 로 본다.
enum VisionSessions {
  /// 체크아웃한 세션과 그 세대.
  struct Lease: Sendable {
    let kind: VisionSession.Kind
    let generation: Int
    let session: VisionSession
    /// 이 세대에서 그 종류의 첫 작업인지(모델을 불러온다).
    let isFirstUse: Bool

    /// 이 작업의 시한. 첫 작업이면 적재를 덮는 긴 시한이다.
    var timeout: Duration {
      self.isFirstUse ? VisionSession.firstUseTimeout : VisionSession.timeout
    }
  }

  /// 버린 이유. Debug 로그의 `reason=` 와 같은 이름이다.
  enum DiscardReason: String {
    case failed
    case timedOut
  }

  private struct State {
    var slot = VisionSessionSlot()
    var session: VisionSession?
  }

  private static let state = Mutex(State())

  static func isAvailable(_ kind: VisionSession.Kind, isAppActive: Bool) -> Bool {
    self.state.withLock { $0.slot.isAvailable(kind, isAppActive: isAppActive) }
  }

  /// 쓸 세션. 앞에서 없으면 만들고(요청 객체만, 가볍다), 쓸 수 없으면 nil.
  static func checkout(_ kind: VisionSession.Kind, isAppActive: Bool) -> Lease? {
    self.state.withLock { state -> Lease? in
      switch state.slot.checkout(kind, isAppActive: isAppActive) {
      case let .use(generation, isFirstUse):
        return state.session.map { Lease(kind: kind, generation: generation, session: $0, isFirstUse: isFirstUse) }
      case let .create(generation):
        let session = VisionSession()
        state.session = session
        return Lease(kind: kind, generation: generation, session: session, isFirstUse: true)
      case .unavailable:
        return nil
      }
    }
  }

  /// 요청이 성공했다. 그 세대에서 그 종류가 처음이면 Debug 에서 준비 로그를 남긴다.
  static func succeeded(_ lease: Lease) {
    let isFirst = self.state.withLock { $0.slot.succeeded(lease.kind, generation: lease.generation) }
    if isFirst {
      self.log("vision session ready", lease.kind, reason: nil)
    }
  }

  /// 그 세대면 세션을 버린다. 앞에서는 다음 요청이 새로 만들고, 뒤에서는 그 뒤 분류·벡터를 하지 않는다.
  static func discard(_ lease: Lease, reason: DiscardReason) {
    let isDiscarded = self.state.withLock { state in
      guard state.slot.discard(generation: lease.generation) else {
        return false
      }
      state.session = nil
      return true
    }
    if isDiscarded {
      self.log("vision session discarded", lease.kind, reason: reason)
    }
  }

  /// 그 세대의 큐가 시한을 넘겼다(`VisionWorkQueue.Hooks.timedOut`). 돌아오지 않은 큐로 세고 그 세대면 버린다.
  static func timedOut(_ lease: Lease, _ info: VisionWorkQueue.TimeoutInfo) {
    let outcome = self.state.withLock { state in
      let result = state.slot.timedOut(generation: lease.generation)
      if result.discarded {
        state.session = nil
      }
      return (discarded: result.discarded, reachedLimit: result.reachedLimit, stuckQueues: state.slot.stuckQueues)
    }
    #if DEBUG
      let isAppActive = FeaturePrinting.availability.withLock(\.isAppActive)
      ImageAnalysisClientImpl.logger.notice(
        """
        vision work timed out kind=\(lease.kind.rawValue, privacy: .public) \
        callerWaiting=\(info.isCallerWaiting ? 1 : 0, privacy: .public) \
        released=\(info.releasedWaiting, privacy: .public) firstUse=\(lease.isFirstUse ? 1 : 0, privacy: .public) \
        active=\(isAppActive ? 1 : 0, privacy: .public)
        """
      )
    #endif
    if outcome.discarded {
      self.log("vision session discarded", lease.kind, reason: .timedOut)
    }
    #if DEBUG
      if outcome.reachedLimit {
        ImageAnalysisClientImpl.logger.notice(
          """
          vision session limit reached stuck=\(outcome.stuckQueues, privacy: .public) \
          active=\(isAppActive ? 1 : 0, privacy: .public)
          """
        )
      }
    #endif
  }

  /// 시한으로 버린 큐의 작업이 늦게 돌아왔다(`VisionWorkQueue.Hooks.ended` 의 `afterTimeout`). 상한 아래로 내려가면 앞에서 다시 만든다.
  static func stuckQueueReturned(_ lease: Lease) {
    self.state.withLock { $0.slot.stuckQueueReturned() }
    self.log("vision work returned", lease.kind, reason: nil)
  }

  /// 정수와 고정 문자열만 남긴다(docs/CONVENTIONS.md §4). Release 에서는 아무것도 하지 않는다.
  private static func log(_ event: String, _ kind: VisionSession.Kind, reason: DiscardReason?) {
    #if DEBUG
      let isAppActive = FeaturePrinting.availability.withLock(\.isAppActive)
      if let reason {
        ImageAnalysisClientImpl.logger.notice(
          """
          \(event, privacy: .public) kind=\(kind.rawValue, privacy: .public) \
          reason=\(reason.rawValue, privacy: .public) active=\(isAppActive ? 1 : 0, privacy: .public)
          """
        )
      } else {
        ImageAnalysisClientImpl.logger.notice(
          """
          \(event, privacy: .public) kind=\(kind.rawValue, privacy: .public) \
          active=\(isAppActive ? 1 : 0, privacy: .public)
          """
        )
      }
    #endif
  }
}
