import PhotoLibraryInterface
import PhotoLibraryTesting
import Synchronization
import Testing
@testable import OnboardingFeature

/// 요청 중 겹침 테스트는 `RequestGate` 로 권한 요청을 붙잡아(팝업이 떠 있는 동안) 그 사이에 복귀·다시 누르기를 보낸 뒤 문을 연다.
@MainActor
struct OnboardingModelTests {
  @Test(
    "생성 시점에 현재 권한 상태를 읽어 둔다",
    arguments: [PhotoAccessState.authorized, .limited, .denied, .notDetermined, .restricted]
  )
  func initReadsCurrentAccess(state: PhotoAccessState) {
    let model = OnboardingModel(photoLibrary: PhotoLibraryClientFake(currentState: state))

    #expect(model.access == state)
  }

  @Test(
    "시작 버튼을 누르면 권한 요청 결과를 반영한다",
    arguments: [PhotoAccessState.authorized, .limited, .denied, .restricted]
  )
  func startButtonTappedRequestsAccess(result: PhotoAccessState) async {
    let model = OnboardingModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: result)
    )

    await model.startButtonTapped()

    #expect(model.access == result)
    #expect(!model.isRequestingAccess)
  }

  @Test("권한 요청 중에는 요청 중 상태가 켜지고 끝나면 꺼진다")
  func requestingAccessWhileWaiting() async {
    let gate = RequestGate()
    let model = OnboardingModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .notDetermined,
        stateAfterRequest: .authorized,
        requestGate: { await gate.pass() }
      )
    )
    let tap = Task { await model.startButtonTapped() }
    await waitUntil { gate.hasEntered }

    #expect(model.isRequestingAccess)
    #expect(model.access == .notDetermined)

    gate.open()
    await tap.value

    #expect(!model.isRequestingAccess)
    #expect(model.access == .authorized)
  }

  @Test("요청 중에 다시 눌러도 권한 요청은 한 번만 한다")
  func repeatedTapRequestsOnce() async {
    let gate = RequestGate()
    let photoLibrary = PhotoLibraryClientFake(
      currentState: .notDetermined,
      stateAfterRequest: .limited,
      requestGate: { await gate.pass() }
    )
    let model = OnboardingModel(photoLibrary: photoLibrary)
    let first = Task { await model.startButtonTapped() }
    await waitUntil { gate.hasEntered }

    await model.startButtonTapped()
    gate.open()
    await first.value

    #expect(photoLibrary.requestAccessCount == 1)
    #expect(model.access == .limited)
  }

  @Test(
    "권한을 이미 정했으면 시작 버튼은 요청하지 않는다",
    arguments: [PhotoAccessState.denied, .restricted, .authorized, .limited]
  )
  func decidedAccessSkipsRequest(state: PhotoAccessState) async {
    let photoLibrary = PhotoLibraryClientFake(currentState: state, stateAfterRequest: .authorized)
    let model = OnboardingModel(photoLibrary: photoLibrary)

    await model.startButtonTapped()

    #expect(photoLibrary.requestAccessCount == 0)
    #expect(model.access == state)
  }

  @Test(
    "앱이 앞으로 돌아오면 권한을 다시 읽는다",
    arguments: [
      (PhotoAccessState.denied, PhotoAccessState.authorized),
      (.denied, .limited),
      (.notDetermined, .denied),
      (.denied, .restricted),
      (.restricted, .denied),
      (.denied, .denied),
      (.notDetermined, .notDetermined),
    ]
  )
  func sceneBecameActiveRereadsAccess(initial: PhotoAccessState, changed: PhotoAccessState) {
    let photoLibrary = PhotoLibraryClientFake(currentState: initial)
    let model = OnboardingModel(photoLibrary: photoLibrary)

    photoLibrary.changeAccessState(changed)
    model.sceneBecameActive()

    #expect(model.access == changed)
  }

  @Test("권한 요청 중 복귀에서 미정으로 읽히면 무시하고 요청 결과를 쓴다", arguments: [PhotoAccessState.authorized, .denied])
  func undeterminedReadWhileRequestingIsIgnored(stateAfterRequest: PhotoAccessState) async {
    let gate = RequestGate()
    let model = OnboardingModel(
      photoLibrary: PhotoLibraryClientFake(
        currentState: .notDetermined,
        stateAfterRequest: stateAfterRequest,
        requestGate: { await gate.pass() }
      )
    )
    let tap = Task { await model.startButtonTapped() }
    await waitUntil { gate.hasEntered }

    model.sceneBecameActive()

    #expect(model.access == .notDetermined)
    #expect(model.isRequestingAccess)

    gate.open()
    await tap.value

    #expect(model.access == stateAfterRequest)
    #expect(!model.isRequestingAccess)
  }

  @Test("권한 요청 중 복귀에서 정해진 권한을 읽으면 바로 반영하고 뒤에 온 요청 결과로 다시 쓴다")
  func decidedReadWhileRequestingIsApplied() async {
    let gate = RequestGate()
    let photoLibrary = PhotoLibraryClientFake(
      currentState: .notDetermined,
      stateAfterRequest: .authorized,
      requestGate: { await gate.pass() }
    )
    let model = OnboardingModel(photoLibrary: photoLibrary)
    let tap = Task { await model.startButtonTapped() }
    await waitUntil { gate.hasEntered }

    photoLibrary.changeAccessState(.denied)
    model.sceneBecameActive()

    #expect(model.access == .denied)
    #expect(model.isRequestingAccess)

    gate.open()
    await tap.value

    #expect(model.access == .authorized)
    #expect(!model.isRequestingAccess)
  }

  @Test("요청 결과가 미정이면 요청 중 복귀로 정한 권한을 덮지 않는다")
  func undeterminedResultKeepsAccessFromReturn() async {
    let gate = RequestGate()
    let photoLibrary = PhotoLibraryClientFake(
      currentState: .notDetermined,
      stateAfterRequest: .notDetermined,
      requestGate: { await gate.pass() }
    )
    let model = OnboardingModel(photoLibrary: photoLibrary)
    let tap = Task { await model.startButtonTapped() }
    await waitUntil { gate.hasEntered }

    photoLibrary.changeAccessState(.limited)
    model.sceneBecameActive()
    gate.open()
    await tap.value

    #expect(model.access == .limited)
    #expect(!model.isRequestingAccess)
  }

  @Test("권한 요청이 끝난 뒤의 복귀는 새 값을 읽는다")
  func sceneBecameActiveAfterRequestReadsNewValue() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .denied)
    let model = OnboardingModel(photoLibrary: photoLibrary)
    await model.startButtonTapped()

    photoLibrary.changeAccessState(.authorized)
    model.sceneBecameActive()

    #expect(model.access == .authorized)
  }

  @Test(
    "이미 정한 권한은 복귀에서 미정으로 되돌리지 않는다",
    arguments: [PhotoAccessState.denied, .limited, .authorized, .restricted]
  )
  func decidedAccessIsNotResetByReturn(initial: PhotoAccessState) {
    let photoLibrary = PhotoLibraryClientFake(currentState: initial)
    let model = OnboardingModel(photoLibrary: photoLibrary)

    photoLibrary.changeAccessState(.notDetermined)
    model.sceneBecameActive()

    #expect(model.access == initial)
  }

  @Test("요청 결과로 정한 권한도 복귀에서 미정으로 되돌리지 않는다")
  func requestResultIsNotResetByReturn() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .authorized)
    let model = OnboardingModel(photoLibrary: photoLibrary)
    await model.startButtonTapped()

    photoLibrary.changeAccessState(.notDetermined)
    model.sceneBecameActive()

    #expect(model.access == .authorized)
  }

  @Test("요청 결과가 미정 그대로 끝나면 시작 버튼으로 다시 요청할 수 있다")
  func undeterminedResultAllowsRetry() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .notDetermined)
    let model = OnboardingModel(photoLibrary: photoLibrary)

    await model.startButtonTapped()

    #expect(model.access == .notDetermined)
    #expect(!model.isRequestingAccess)

    await model.startButtonTapped()

    #expect(photoLibrary.requestAccessCount == 2)
  }
}

/// 권한 팝업이 떠 있는 동안을 흉내 내는 문. 요청이 들어온 것을 기록하고 `open()` 까지 기다린다.
/// 들어오기 전에 열면 바로 지나간다. Task 가 취소되면 기다림이 끝난다.
final class RequestGate: Sendable {
  private let entered = Mutex(false)
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: Void.self)
  }

  var hasEntered: Bool {
    self.entered.withLock { $0 }
  }

  func pass() async {
    self.entered.withLock { $0 = true }
    for await _ in self.stream {}
  }

  func open() {
    self.continuation.finish()
  }
}

/// 조건이 맞을 때까지 짧게 잠들며 기다린다. Fake 의 async 메서드는 전역 실행기에서 돌아 끝나는 시점이 스케줄링에 달렸으므로,
/// 반복 횟수가 아니라 시간으로 제한하고 부하를 견딜 만큼 넉넉히 둔다(LibraryFeature 테스트의 같은 이름 헬퍼와 같은 방식).
@MainActor
func waitUntil(timeout: Duration = .seconds(30), _ condition: () -> Bool) async {
  let deadline = ContinuousClock.now + timeout
  while !condition(), ContinuousClock.now < deadline {
    do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
  }
  #expect(condition(), "기다리던 상태가 되지 않았다")
}
