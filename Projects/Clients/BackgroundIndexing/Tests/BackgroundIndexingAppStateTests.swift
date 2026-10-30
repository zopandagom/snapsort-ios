import Foundation
import IndexingInterface
import Testing
@testable import BackgroundIndexingImpl

/// 앱이 뒤로 가고 앞으로 올 때 실행 시간 빌리기·제출·저장소 출입 맞추기 순서.
@MainActor
struct BackgroundIndexingAppStateTests {
  @Test("앱이 뒤로 가면 시간을 빌리고 제출한 뒤 저장소에서 손 뗄 때까지 기다리고 돌려준다")
  func enterBackgroundOrder() async {
    let coordinator = Coordinator()

    coordinator.impl.appDidEnterBackground()
    await waitUntil { coordinator.log.count("end(1)") == 1 }

    #expect(coordinator.log.all == [
      "activity(false)", "begin(1)", "submit", "hold", "waitUntilStoreReleased", "end(1)",
    ])
  }

  @Test("뒤로 가자마자 돌아오면 마지막 적용이 출입 허용이고 빌린 시간은 한 번 돌려준다")
  func returnsBeforeSettleFinishes() async {
    let coordinator = Coordinator()

    coordinator.impl.appDidEnterBackground()
    coordinator.impl.appDidBecomeActive()
    await waitUntil { coordinator.log.count("end(1)") == 1 }
    try? await Task.sleep(for: .milliseconds(50))

    let log = coordinator.log.all
    #expect(log.last(where: { $0 == "hold" || $0 == "allow" }) == "allow")
    #expect(coordinator.log.count("end(1)") == 1)
    #expect(coordinator.log.count("submit") == 1)
    #expect(Array(log.prefix(3)) == ["activity(false)", "begin(1)", "submit"])
    #expect(log.contains("activity(true)"))
  }

  @Test("같은 상태 이벤트가 다시 오면 아무것도 하지 않는다")
  func ignoresRepeatedEvents() async {
    let coordinator = Coordinator()

    coordinator.impl.appDidBecomeActive()
    coordinator.impl.appDidEnterBackground()
    coordinator.impl.appDidEnterBackground()
    await waitUntil { coordinator.log.count("end(1)") == 1 }

    #expect(coordinator.log.count("activity(true)") == 0)
    #expect(coordinator.log.count("activity(false)") == 1)
    #expect(coordinator.log.count("begin(1)") == 1)
  }

  @Test("BG 작업 중 앱이 뒤로 가면 시간을 빌리지도 제출하지도 않는다")
  func enterBackgroundDuringTask() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    coordinator.impl.appDidEnterBackground()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(!coordinator.log.all.contains { $0.hasPrefix("begin") })
    #expect(coordinator.log.count("submit") == 0)
    gate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
  }

  @Test("빌린 시간이 만료되면 한 번만 돌려준다")
  func assertionExpiration() async {
    let coordinator = Coordinator()

    coordinator.impl.appDidEnterBackground()
    coordinator.application.expireAssertion()
    coordinator.application.expireAssertion()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(coordinator.log.count("end(1)") == 1)
  }

  @Test("앱이 뒤에 있을 때 작업이 시작되면 실행기에 비활성을 알린다")
  func handlerReadsApplicationState() async throws {
    let coordinator = Coordinator(isActive: false)

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(try #require(coordinator.log.index(of: "activity(false)")) < coordinator.log.index(of: "runInBackground")!)
  }

  @Test("앱을 띄운 BG 작업 중 앱이 앞으로 오면 활성을 알리고 마지막 적용이 출입 허용이다")
  func becomesActiveDuringColdLaunch() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) }, isActive: false)

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    coordinator.impl.appDidBecomeActive()
    gate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    let log = coordinator.log.all
    #expect(log.contains("activity(true)"))
    #expect(log.last(where: { $0 == "hold" || $0 == "allow" }) == "allow")
  }

  @Test("빌린 시간이 남은 채 작업이 시작되면 그 시간을 한 번 돌려준다")
  func handlerEndsRemainingAssertion() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) }, isActive: false)

    coordinator.impl.appDidEnterBackground()
    _ = coordinator.launch()
    gate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
    try? await Task.sleep(for: .milliseconds(50))

    #expect(coordinator.log.count("end(1)") == 1)
  }

  @Test("시스템이 만료 핸들러를 메인 밖에서 불러도 죽지 않고 실패로 한 번 완료한다")
  func expirationOffMainThread() async throws {
    let gate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: gate) },
      isActive: false
    )

    let task = coordinator.launch()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    // BGTask.h 는 만료 핸들러를 부르는 스레드를 정하지 않는다. 메인 밖에서 불러 격리 확인에 걸리지 않는지 본다.
    nonisolated(unsafe) let handler = try #require(task.expirationHandler)
    await Task.detached { handler() }.value
    await waitUntil { coordinator.log.count("completed(false)") == 1 }

    #expect(coordinator.log.count("completed(false)") == 1)
    #expect(coordinator.log.count("completed(true)") == 0)
  }
}
