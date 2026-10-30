import Core
import CoreML
import Foundation
import ImageAnalysisInterface
import Synchronization
import Vision

/// Vision 특징 벡터 요청의 설정·변환·시한 (docs/ARCHITECTURE.md §4 정리 도우미).
enum FeaturePrinting {
  /// 요청 revision. 바꾸면 `ImageFeaturePrint.version` 을 올린다(테스트가 대조한다).
  static let revision = GenerateImageFeaturePrintRequest.Revision.revision2
  /// `revision` 의 번호. `ImageFeaturePrint.version / 10_000` 과 같아야 한다.
  static let revisionNumber = 2

  /// 요청 하나의 시한(임시 값). iOS 27 시뮬레이터 GPU 에서 요청이 10분 넘게 돌아오지 않은 실측이 있어 둔다.
  /// Mac 장당 4.8ms, iOS 27 시뮬레이터 CPU 첫 호출 0.29s·이후 72ms. 실기기 첫 호출(모델 적재)을 넉넉히 덮는 값으로 잡고 실기기에서 조정한다.
  /// 넘기면 앞·뒤로 나눠 막는다(`FeaturePrintAvailability`). 뒤(앱이 뒤에 있을 때)에서 시작한 요청은 CPU 로 계산한다(`pinToCPU`).
  static let timeout: Duration = .seconds(5)

  /// 이 기기에서 특징 벡터를 만들 수 있는지. 시뮬레이터는 Vision 이 실패하거나 멈추거나 모든 사진에 같은 벡터를 준다.
  /// 이 상수만 조건부로 두고 Vision 호출 코드는 늘 컴파일해, 시뮬레이터·CI 빌드도 실기기 경로를 검사한다.
  static let isSupportedDevice: Bool = {
    #if targetEnvironment(simulator)
      false
    #else
      true
    #endif
  }()

  /// 지금 쓸 수 있는지와 앱 활성 상태. 요청이 시한을 넘기면 앞·뒤 차단을 걸어 프로세스가 끝날 때까지 두고, 막힌 동안 요청은 Vision 을 부르지 않는다.
  /// 프로세스에 하나라 같은 프로세스의 모든 `ImageAnalysisClientImpl` 값이 같이 본다.
  /// 테스트는 이 값을 바꾸지 않는다(같은 프로세스의 Impl 테스트끼리 나눈다). 바꾸는 판정은 `handle(_:)` 와 값 타입 `FeaturePrintAvailability` 로만
  /// 테스트한다(`ImageAnalysisClientImpl.appActivityChanged` 도 이 값을 바꾸므로 Impl 테스트에서 부르지 않는다).
  static let availability = Mutex(FeaturePrintAvailability(isSupportedDevice: Self.isSupportedDevice))

  /// 요청의 주 계산 단계를 CPU 로 고정한다. 그 런타임이 주 단계에 CPU 를 지원하지 않으면 바꾸지 않는다(기본 장치).
  /// 반드시 제네릭 `VisionRequest` 경유(프로토콜 witness)로 부른다: macOS 26.6 런타임에서 `GenerateImageFeaturePrintRequest` 의
  /// `supportedComputeStageDevices` 를 구조체로 직접 부르면 dyld 가 심볼을 못 찾아 실행 시작에서 죽었다(실측). 그래서 최적화가 이 함수를
  /// 구체 타입으로 특수화해 직접 호출로 바꾸지 않게 막는다(Release 산출물 `nm -u` 로 확인, docs/ARCHITECTURE.md §4 정리 도우미).
  @inline(never)
  @_semantics("optimize.sil.specialize.generic.never")
  static func pinToCPU(_ request: inout some VisionRequest) {
    guard let cpu = cpuDevice(in: request.supportedComputeStageDevices[.main] ?? []) else { return }
    request.setComputeDevice(cpu, for: .main)
  }

  /// 장치 목록에서 CPU 를 고른다. 없으면 nil.
  static func cpuDevice(in devices: [MLComputeDevice]) -> MLComputeDevice? {
    devices.first { device in
      if case .cpu = device {
        return true
      }
      return false
    }
  }

  /// Vision 결과를 Core 값으로 바꾼다. Float 원소이고 개수가 `ImageFeaturePrint.elementCount` 이고 데이터 길이가 맞을 때만 값이다.
  /// revision 2 는 Float 768 개다(실측). Double 이면 저장 형식과 달라 nil.
  static func featurePrint(data: Data, elementType: ElementType, elementCount: Int) -> ImageFeaturePrint? {
    guard elementType == .float, elementCount == ImageFeaturePrint.elementCount else {
      return nil
    }
    return ImageFeaturePrint(floatData: data)
  }

  /// `race` 의 결과.
  enum RaceOutcome<Output: Sendable>: Sendable {
    case completed(Output)
    case timedOut
  }

  /// 경주 결과를 요청 결과로 바꾼다. 시한을 넘기면 `.failed` 이고 시한 차단을 걸어야 한다(`makesUnavailable`, 앞·뒤 판정은 `FeaturePrintAvailability`).
  static func handle(
    _ outcome: RaceOutcome<ImageFeaturePrint>
  ) -> (result: Result<ImageFeaturePrint, ImageAnalysisError>, makesUnavailable: Bool) {
    switch outcome {
    case let .completed(featurePrint):
      (.success(featurePrint), false)
    case .timedOut:
      (.failure(.failed), true)
    }
  }

  /// `operation` 을 시한과 경주시킨다. 먼저 끝난 쪽이 결과가 되고 다른 쪽은 취소한다.
  /// 구조적 동시성(`withTaskGroup`)은 자식이 끝날 때까지 기다리므로 취소에 응답하지 않는 Vision 요청에 묶인다. 그래서 비구조 Task 두 개와
  /// 한 번만 재개하는 continuation 으로 경주한다. 시한을 넘긴 `operation` 은 끝까지(또는 영원히) 돌 수 있고 그 결과는 버린다.
  /// 부른 Task 가 취소되면 `.cancelled` 를 던진다. `operation` 이 던진 실패는 그대로 던진다.
  static func race<Output: Sendable>(
    timeout: Duration,
    _ operation: @escaping @Sendable () async throws(ImageAnalysisError) -> Output
  ) async throws(ImageAnalysisError) -> RaceOutcome<Output> {
    let race = FeaturePrintRace<Output>()
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard race.install(continuation) else {
          return
        }
        let work = Task {
          do throws(ImageAnalysisError) {
            try await race.finish(.success(.completed(operation())))
          } catch {
            race.finish(.failure(error))
          }
        }
        let timer = Task {
          try? await Task.sleep(for: timeout)
          if !Task.isCancelled {
            race.finish(.success(.timedOut))
          }
        }
        race.track([work, timer])
      }
    } onCancel: {
      race.finish(.failure(.cancelled))
    }
    return try result.get()
  }
}

/// `FeaturePrinting.race` 의 경주 상태. continuation 을 한 번만 재개하고, 재개하면 남은 Task 를 취소한다.
private final class FeaturePrintRace<Output: Sendable>: Sendable {
  typealias Outcome = Result<FeaturePrinting.RaceOutcome<Output>, ImageAnalysisError>
  /// 잠금 밖에서 재개할 continuation 과 취소할 Task.
  private typealias Handoff = (continuation: CheckedContinuation<Outcome, Never>?, tasks: [Task<Void, Never>])

  private struct State {
    var continuation: CheckedContinuation<Outcome, Never>?
    /// continuation 을 받기 전에 끝난 결과(부른 Task 가 이미 취소됨).
    var early: Outcome?
    var isFinished = false
    var tasks: [Task<Void, Never>] = []
  }

  private let state = Mutex(State())

  /// continuation 을 받는다. 이미 끝났으면 바로 재개하고 false(Task 를 시작하지 않는다).
  func install(_ continuation: CheckedContinuation<Outcome, Never>) -> Bool {
    let early: Outcome? = self.state.withLock { state in
      if let early = state.early {
        return early
      }
      state.continuation = continuation
      return nil
    }
    if let early {
      continuation.resume(returning: early)
      return false
    }
    return true
  }

  /// 시작한 Task 를 기록한다. 이미 끝났으면 바로 취소한다.
  func track(_ tasks: [Task<Void, Never>]) {
    let isFinished = self.state.withLock { state in
      state.tasks = tasks
      return state.isFinished
    }
    if isFinished {
      tasks.forEach { $0.cancel() }
    }
  }

  /// 처음 온 결과만 쓴다. 늦게 온 결과는 버린다.
  func finish(_ result: Outcome) {
    let (continuation, tasks) = self.state.withLock { state -> Handoff in
      guard !state.isFinished else {
        return (nil, [])
      }
      state.isFinished = true
      guard let continuation = state.continuation else {
        state.early = result
        return (nil, [])
      }
      state.continuation = nil
      return (continuation, state.tasks)
    }
    continuation?.resume(returning: result)
    tasks.forEach { $0.cancel() }
  }
}
