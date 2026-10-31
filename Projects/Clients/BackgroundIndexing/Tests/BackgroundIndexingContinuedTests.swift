import BackgroundIndexingInterface
import BackgroundTasks
import Foundation
import IndexingInterface
import Testing
@testable import BackgroundIndexingImpl

/// 계속 처리 작업: 등록·요청·제출 실패·핸들러와 앱 상태·발열 (설계 §11.1). 진행 표시·끝은 BackgroundIndexingContinuedFinishTests.
@MainActor
struct BackgroundIndexingContinuedTests {
  // MARK: - 등록·요청

  @Test("두 식별자를 한 번씩 등록하고, 두 번 불러도 다시 등록하지 않으며 상태가 요청 가능이 된다")
  func registersBothIdentifiersOnce() {
    let coordinator = Coordinator()
    #expect(coordinator.impl.continuedIndexingState == .unsupported)

    coordinator.impl.registerLaunchHandler()
    coordinator.impl.registerLaunchHandler()

    #expect(coordinator.scheduler.registeredIdentifiers == [Coordinator.identifier])
    #expect(coordinator.scheduler.registeredContinuedIdentifiers == [Coordinator.continuedIdentifier])
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }

  @Test("식별자가 없거나 등록이 안 되거나 저장소가 없으면 쓸 수 없고, 요청은 제출하지 않는다")
  func unsupportedWithoutIdentifierRegistrationOrStore() {
    let withoutIdentifier = Coordinator(continuedIdentifier: nil)
    let notRegistered = Coordinator()
    notRegistered.scheduler.continuedRegisterResult = false
    let withoutStore = Coordinator(indexing: { _ in nil })

    for coordinator in [withoutIdentifier, notRegistered, withoutStore] {
      coordinator.impl.registerLaunchHandler()

      #expect(coordinator.impl.continuedIndexingState == .unsupported)
      #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .unavailable)
      #expect(coordinator.scheduler.continuedSubmissions.isEmpty)
    }
    #expect(withoutIdentifier.scheduler.registeredContinuedIdentifiers.isEmpty)
  }

  @Test("앞에서 요청하면 준비 문구로 한 번 제출하고, 도는 동안 다시 요청해도 제출하지 않는다")
  func submitsOnceInForeground() {
    let coordinator = Coordinator()
    coordinator.impl.registerLaunchHandler()

    let first = coordinator.impl.requestContinuedIndexing(text: .test)
    let second = coordinator.impl.requestContinuedIndexing(text: .test)

    #expect(first == .started)
    #expect(second == .started)
    #expect(coordinator.scheduler.continuedSubmissions == [
      SchedulerDouble.ContinuedSubmission(
        identifier: Coordinator.continuedIdentifier,
        title: "preparing",
        subtitle: "0/0"
      ),
    ])
    #expect(coordinator.impl.continuedIndexingState == .active)
  }

  @Test("앱이 뒤에 있으면 제출하지 않고 나중에 다시 요청할 수 있다")
  func skipsInBackground() {
    let coordinator = Coordinator()
    coordinator.impl.registerLaunchHandler()
    coordinator.impl.appDidEnterBackground()

    #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .temporarilyUnavailable)
    #expect(coordinator.scheduler.continuedSubmissions.isEmpty)
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }

  @Test("바로 돌릴 수 없음·요청 수 초과면 나중에 다시 요청할 수 있고 처리 작업을 제출하지 않는다", arguments: [
    BGTaskScheduler.Error.Code.immediateRunIneligible,
    .tooManyPendingTaskRequests,
  ])
  func temporarySubmitFailure(code: BGTaskScheduler.Error.Code) {
    let coordinator = Coordinator()
    coordinator.impl.registerLaunchHandler()
    coordinator.scheduler.continuedSubmitError = BGTaskScheduler.Error(code)

    #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .temporarilyUnavailable)
    #expect(coordinator.impl.continuedIndexingState == .idle)
    #expect(coordinator.log.count("submit") == 0)

    #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .temporarilyUnavailable)
    #expect(coordinator.scheduler.continuedSubmissions.count == 2)
  }

  @Test("지원 안 함·허용 안 됨이면 이 실행에서는 쓸 수 없고 다시 제출하지 않으며 처리 작업을 제출하지 않는다", arguments: [
    BGTaskScheduler.Error.Code.unavailable,
    .notPermitted,
  ])
  func permanentSubmitFailure(code: BGTaskScheduler.Error.Code) {
    let coordinator = Coordinator()
    coordinator.impl.registerLaunchHandler()
    coordinator.scheduler.continuedSubmitError = BGTaskScheduler.Error(code)

    #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .unavailable)
    #expect(coordinator.impl.continuedIndexingState == .unsupported)
    #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .unavailable)
    #expect(coordinator.scheduler.continuedSubmissions.count == 1)
    #expect(coordinator.log.count("submit") == 0)
  }

  // MARK: - 핸들러와 앱 상태

  @Test("계속 처리 작업이 쥔 채 앱이 뒤로 가면 시간을 빌리지도 처리 작업을 제출하지도 않고 저장소 출입을 연 채 둔다")
  func enterBackgroundWhileHolding() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    coordinator.impl.appDidEnterBackground()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(!coordinator.log.all.contains { $0.hasPrefix("begin") })
    #expect(coordinator.log.count("submit") == 0)
    #expect(coordinator.log.count("hold") == 0)
    #expect(coordinator.log.all.last { $0 == "hold" || $0 == "allow" } == "allow")
    gate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("계속 처리 중 앱이 앞으로 와도 작업을 놓지 않고, 다시 뒤로 가도 시간을 빌리지 않는다")
  func keepsHoldingAcrossForeground() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    coordinator.impl.appDidEnterBackground()
    coordinator.impl.appDidBecomeActive()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(coordinator.log.count("activity(true)") == 1)
    #expect(!coordinator.log.all.contains { $0.hasPrefix("continuedCompleted") })
    #expect(coordinator.impl.continuedIndexingState == .active)

    coordinator.impl.appDidEnterBackground()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!coordinator.log.all.contains { $0.hasPrefix("begin") })
    gate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("뒤에서 기기가 뜨거우면 시작하지 않고 처리 작업을 제출한 뒤 실패로 끝낸다")
  func rejectsWhenHotInBackground() {
    let coordinator = Coordinator()
    coordinator.impl.registerLaunchHandler()
    _ = coordinator.impl.requestContinuedIndexing(text: .test)
    coordinator.impl.appDidEnterBackground()
    coordinator.thermal.value = .serious

    coordinator.scheduler.launchContinued(ContinuedTaskDouble(log: coordinator.log))

    #expect(coordinator.log.count("runInBackground") == 0)
    #expect(coordinator.log.count("submit") == 2)
    #expect(coordinator.log.count("continuedCompleted(false)") == 1)
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }

  @Test("앞에서는 뜨거워도 시작하고, 앱 상태를 직접 읽지 않아 실행기에 비활성을 알리지 않는다")
  func startsWhenHotInForeground() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) }, isActive: false)
    coordinator.thermal.value = .critical

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }

    #expect(coordinator.log.count("activity(false)") == 0)
    #expect(coordinator.log.count("submit") == 0)
    gate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("핸들러가 오기 전 앱이 뒤로 가면 지금처럼 빌리고 처리 작업을 제출하고, 핸들러가 오면 빌린 시간을 돌려준다")
  func pendingThenBackground() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })
    coordinator.impl.registerLaunchHandler()
    _ = coordinator.impl.requestContinuedIndexing(text: .test)

    coordinator.impl.appDidEnterBackground()
    #expect(Array(coordinator.log.all.prefix(4)) == ["submitContinued", "activity(false)", "begin(1)", "submit"])

    coordinator.scheduler.launchContinued(ContinuedTaskDouble(log: coordinator.log))
    await waitUntil { coordinator.log.count("end(1)") == 1 && coordinator.log.count("runInBackground") == 1 }
    gate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    #expect(coordinator.log.count("end(1)") == 1)
  }

  @Test("핸들러가 오지 않은 채 앱이 다시 앞으로 오면 요청 가능으로 돌아가고, 늦게 온 핸들러는 정상 시작해 한 번 완료한다")
  func pendingResetsOnForegroundAndLateHandlerRuns() async {
    let coordinator = Coordinator()
    coordinator.impl.registerLaunchHandler()
    _ = coordinator.impl.requestContinuedIndexing(text: .test)
    #expect(coordinator.impl.continuedIndexingState == .active)

    coordinator.impl.appDidEnterBackground()
    coordinator.impl.appDidBecomeActive()
    #expect(coordinator.impl.continuedIndexingState == .idle)

    coordinator.scheduler.launchContinued(ContinuedTaskDouble(log: coordinator.log))
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    try? await Task.sleep(for: .milliseconds(50))

    #expect(coordinator.log.count("runInBackground") == 1)
    #expect(coordinator.log.all.count { $0.hasPrefix("continuedCompleted") } == 1)
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }
}
