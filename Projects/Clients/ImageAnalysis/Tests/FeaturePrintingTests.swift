import Core
import CoreML
import Foundation
import ImageAnalysisInterface
import Synchronization
import Testing
import Vision
@testable import ImageAnalysisImpl

/// 실제 벡터 계산(`ImageAnalysisClientImpl.featurePrint` 가 Vision 을 부르는 경로)은 자동 테스트가 없다. 시뮬레이터의 Vision 은
/// 요청이 실패하거나 멈추거나 모든 사진에 같은 벡터를 주고, Client 테스트는 호스트 앱이 없어 실기기에서 돌 수 없다(docs/CONVENTIONS.md §3).
/// 그래서 결과 변환·시한 경주·시뮬레이터 경로·버전 대조만 테스트한다. 전역 `FeaturePrinting.availability` 는 바꾸지 않는다
/// (같은 프로세스의 Impl 테스트끼리 나눈다). 시한 초과로 쓸 수 없게 바꾸는 판정은 `handle(_:)` 와 `FeaturePrintAvailabilityTests` 로 본다.
/// 같은 이유로 `ImageAnalysisClientImpl.appActivityChanged` 도 부르지 않는다.
struct FeaturePrintingTests {
  private static func floatData(_ values: [Float]) -> Data {
    values.withUnsafeBytes { Data($0) }
  }

  @Test("Float 768 개면 값으로 바꾼다")
  func convertsFloatData() {
    let values = (0 ..< 768).map { Float($0) / 768 }

    let featurePrint = FeaturePrinting.featurePrint(
      data: Self.floatData(values),
      elementType: .float,
      elementCount: 768
    )

    #expect(featurePrint?.values == values)
  }

  @Test("Double 원소, 개수 다름, 데이터 길이 다름이면 nil 이다")
  func rejectsUnexpectedShape() {
    let values = [Float](repeating: 0.5, count: 768)
    let doubles = [Double](repeating: 0.5, count: 768).withUnsafeBytes { Data($0) }

    #expect(FeaturePrinting.featurePrint(data: doubles, elementType: .double, elementCount: 768) == nil)
    #expect(FeaturePrinting.featurePrint(data: Self.floatData(values), elementType: .double, elementCount: 768) == nil)
    #expect(FeaturePrinting.featurePrint(data: Self.floatData(values), elementType: .float, elementCount: 767) == nil)
    #expect(FeaturePrinting.featurePrint(
      data: Self.floatData(Array(values.dropLast())),
      elementType: .float,
      elementCount: 768
    ) == nil)
  }

  @Test("요청 revision 과 썸네일 크기가 특징 벡터 버전과 맞는다")
  func versionMatchesRequest() {
    #expect(FeaturePrinting.revision == .revision2)
    #expect(ImageFeaturePrint.version / 10000 == FeaturePrinting.revisionNumber)
    #expect(GenerateImageFeaturePrintRequest.supportedRevisions.contains(FeaturePrinting.revision))
  }

  @Test("시한 초과는 실패이고 쓸 수 없음으로 바꾸며, 끝난 결과는 그대로 쓴다")
  func handlesOutcome() throws {
    let featurePrint = try #require(ImageFeaturePrint(values: [Float](repeating: 0, count: 768)))

    let completed = FeaturePrinting.handle(.completed(featurePrint))
    let timedOut = FeaturePrinting.handle(.timedOut)

    #expect(completed.result == .success(featurePrint))
    #expect(!completed.makesUnavailable)
    #expect(timedOut.result == .failure(.failed))
    #expect(timedOut.makesUnavailable)
  }

  @Test("시한 안에 끝나면 결과를 돌려준다")
  func raceCompletes() async throws {
    let outcome = try await FeaturePrinting.race(timeout: .seconds(10)) { () async throws(ImageAnalysisError) in 7 }

    guard case let .completed(value) = outcome else {
      Issue.record("시한 안에 끝난 연산이 \(outcome) 로 돌아왔다")
      return
    }
    #expect(value == 7)
  }

  @Test("연산이 던진 실패는 그대로 던진다")
  func raceRethrows() async {
    await #expect(throws: ImageAnalysisError.failed) {
      try await FeaturePrinting.race(timeout: .seconds(10)) { () async throws(ImageAnalysisError) -> Int in
        throw .failed
      }
    }
  }

  @Test("취소에 응답하지 않는 연산이 시한을 넘기면 시한 초과로 돌아오고, 늦게 끝난 결과는 버린다")
  func raceTimesOut() async throws {
    let gate = Gate()
    let (finished, finishedSignal) = AsyncStream.makeStream(of: Void.self)

    let outcome = try await FeaturePrinting.race(timeout: .milliseconds(50)) { () async throws(ImageAnalysisError) in
      await gate.wait()
      finishedSignal.yield()
      return 1
    }

    guard case .timedOut = outcome else {
      Issue.record("시한을 넘긴 연산이 \(outcome) 로 돌아왔다")
      return
    }
    // 매달린 Task 를 남기지 않도록 연산을 끝낸다. 늦은 결과로 continuation 을 두 번 재개하면 여기서 멈춘다(CheckedContinuation 검사).
    gate.open()
    var iterator = finished.makeAsyncIterator()
    await iterator.next()
    try await Task.sleep(for: .milliseconds(20))
  }

  @Test("부른 Task 가 취소되면 연산을 기다리지 않고 취소를 던진다")
  func raceCancelled() async {
    let gate = Gate()
    let (started, startedSignal) = AsyncStream.makeStream(of: Void.self)
    let task = Task { () async -> ImageAnalysisError? in
      do throws(ImageAnalysisError) {
        _ = try await FeaturePrinting.race(timeout: .seconds(60)) { () async throws(ImageAnalysisError) in
          startedSignal.yield()
          await gate.wait()
          return 1
        }
        return nil
      } catch {
        return error
      }
    }
    var iterator = started.makeAsyncIterator()
    await iterator.next()
    task.cancel()

    #expect(await task.value == .cancelled)
    gate.open()
  }

  @Test("이미 취소된 Task 에서 부르면 연산을 시작하지 않고 취소를 던진다")
  func raceAlreadyCancelled() async {
    let calls = Mutex(0)
    let task = Task { () async -> ImageAnalysisError? in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        _ = try await FeaturePrinting.race(timeout: .seconds(60)) { () async throws(ImageAnalysisError) in
          calls.withLock { $0 += 1 }
          return 1
        }
        return nil
      } catch {
        return error
      }
    }

    #expect(await task.value == .cancelled)
    #expect(calls.withLock { $0 } == 0)
  }

  @Test("시뮬레이터에서는 쓸 수 없고 Vision 을 부르지 않고 바로 실패한다", .enabled(if: !FeaturePrinting.isSupportedDevice))
  func simulatorIsUnavailable() async {
    let client = ImageAnalysisClientImpl()

    #expect(!client.isFeaturePrintAvailable)
    await #expect(throws: ImageAnalysisError.failed) { try await client.featurePrint(.stub()) }
  }

  @Test("쓸 수 없을 때 취소된 Task 면 취소를 던진다", .enabled(if: !FeaturePrinting.isSupportedDevice))
  func simulatorCancelled() async {
    let task = Task { () async -> ImageAnalysisError? in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageAnalysisError) {
        _ = try await ImageAnalysisClientImpl().featurePrint(.stub())
        return nil
      } catch {
        return error
      }
    }

    #expect(await task.value == .cancelled)
  }
}

/// 테스트가 열 때까지 기다리게 하는 문. 취소에 응답하지 않는 연산을 흉내 내고, 테스트 끝에 열어 매달린 Task 를 남기지 않는다.
private final class Gate: Sendable {
  private struct State {
    var isOpen = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  func wait() async {
    await withCheckedContinuation { continuation in
      let isOpen = self.state.withLock { state in
        if !state.isOpen {
          state.waiters.append(continuation)
        }
        return state.isOpen
      }
      if isOpen {
        continuation.resume()
      }
    }
  }

  func open() {
    let waiters = self.state.withLock { state in
      state.isOpen = true
      defer { state.waiters = [] }
      return state.waiters
    }
    waiters.forEach { $0.resume() }
  }

  @Test("장치 목록에서 CPU 를 고르고, CPU 가 없거나 비었으면 nil 이다")
  func picksCPUDevice() {
    let all = MLComputeDevice.allComputeDevices
    let withoutCPU = all.filter { !Self.isCPU($0) }

    #expect(FeaturePrinting.cpuDevice(in: all).map(Self.isCPU) == true)
    #expect(FeaturePrinting.cpuDevice(in: withoutCPU) == nil)
    #expect(FeaturePrinting.cpuDevice(in: []) == nil)
  }

  @Test("CPU 고정은 그 런타임이 주 단계에 CPU 를 지원하면 CPU 로 바꾸고, 아니면 기본 장치(nil)로 둔다")
  func pinsFeaturePrintRequestToCPU() {
    var request = GenerateImageFeaturePrintRequest(FeaturePrinting.revision)
    // 로컬 목록으로 기대를 고정하지 않는다(CI 러너와 런타임이 다를 수 있다).
    let supportsCPU = Self.mainDevices(of: request).contains(where: Self.isCPU)

    FeaturePrinting.pinToCPU(&request)

    if supportsCPU {
      #expect(Self.mainDevice(of: request).map(Self.isCPU) == true)
    } else {
      #expect(Self.mainDevice(of: request) == nil)
    }
  }

  private static func isCPU(_ device: MLComputeDevice) -> Bool {
    if case .cpu = device {
      return true
    }
    return false
  }

  // 구조체로 직접 부르면 iOS 26 런타임에서 dyld 가 심볼을 못 찾을 수 있어 Impl 과 같이 제네릭 `VisionRequest` 로 부른다.
  private static func mainDevices(of request: some VisionRequest) -> [MLComputeDevice] {
    request.supportedComputeStageDevices[.main] ?? []
  }

  private static func mainDevice(of request: some VisionRequest) -> MLComputeDevice? {
    request.computeDevice(for: .main)
  }
}
