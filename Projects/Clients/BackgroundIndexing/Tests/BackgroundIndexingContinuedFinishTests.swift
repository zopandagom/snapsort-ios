import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import Testing
@testable import BackgroundIndexingImpl

/// 계속 처리 작업의 진행 표시와 끝(할 일 끝·만료·남은 일·위젯) (설계 §11.1, 라운드 2 반영 5).
@MainActor
struct BackgroundIndexingContinuedFinishTests {
  // MARK: - 진행 표시

  @Test("진행률마다 막대를 갱신하고 문구는 바뀔 때만 보내며, 끝나면 막대를 채운다")
  func showsProgressAndTitle() async {
    let gate = Gate()
    let coordinator = Coordinator(
      indexing: {
        IndexingDouble(log: $0, progress: [.classifying, .classifying, .recognizingText, .finished], gate: gate)
      },
      tripPlace: { _ in nil }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.displayLog == [
      "progress(0,0)",
      "progress(0,8)", "title(classifying,2/10)",
      "progress(0,8)",
      "progress(8,11)", "title(recognizingText,0/3)",
      "progress(11,11)",
      "progress(11,11)",
    ])
    #expect(coordinator.log.count("runInBackground.cancelled") == 1)
  }

  // MARK: - 끝

  @Test("앞에서 분류·글자 읽기가 끝나면 hold 만 놓고 회차가 끝난 뒤 처리 작업 제출 없이 성공으로 끝낸다")
  func finishesInForegroundAfterRound() async throws {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText, .finished], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 && coordinator.log.count("prefetch") == 1
    }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!coordinator.log.all.contains { $0.hasPrefix("continuedCompleted") })
    #expect(coordinator.impl.continuedIndexingState == .active)

    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    let log = coordinator.log
    #expect(log.count("prefetch.cancelled") == 0)
    #expect(log.count("submit") == 0)
    #expect(try #require(log.all.lastIndex(of: "allow")) < log.index(of: "continuedCompleted(true)")!)
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }

  @Test("뒤에서 끝나면 저장소에서 손 뗀 뒤 처리 작업을 제출하고 성공으로 끝낸다")
  func finishesInBackground() async throws {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: {
        TripPlaceDouble(log: $0, rounds: [.init(progress: [.init(doneCount: 0, totalCount: 0)], gate: tripGate)])
      }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.impl.appDidEnterBackground()
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    let log = coordinator.log
    let hold = try #require(log.index(of: "hold"))
    let wait = try #require(log.all.lastIndex(of: "waitUntilStoreReleased"))
    let submit = try #require(log.index(of: "submit"))
    let filled = try #require(log.all.lastIndex(of: "progress(3,3)"))
    let completed = try #require(log.index(of: "continuedCompleted(true)"))
    #expect(filled < hold)
    #expect(hold < wait)
    #expect(wait < submit)
    #expect(submit < completed)
    #expect(log.count("prefetch") == 1)
  }

  @Test("만료(사용자 취소)되면 실행·회차를 취소하고 손 뗀 뒤 처리 작업을 제출하고 실패로 한 번 끝낸다")
  func expirationOrder() async throws {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    let task = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 && coordinator.log.count("runInBackground") == 1 }
    coordinator.impl.appDidEnterBackground()
    task.expire()
    task.expire()
    await waitUntil { coordinator.log.count("continuedCompleted(false)") == 1 }

    let log = coordinator.log
    let cancelled = try #require(log.index(of: "runInBackground.cancelled"))
    let prefetchCancelled = try #require(log.index(of: "prefetch.cancelled"))
    let hold = try #require(log.all.lastIndex(of: "hold"))
    let wait = try #require(log.all.lastIndex(of: "waitUntilStoreReleased"))
    let submit = try #require(log.index(of: "submit"))
    let completed = try #require(log.index(of: "continuedCompleted(false)"))
    #expect(cancelled < hold)
    #expect(prefetchCancelled < hold)
    #expect(hold < wait)
    #expect(wait < submit)
    #expect(submit < completed)
    #expect(log.all.count { $0.hasPrefix("continuedCompleted") } == 1)
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }

  @Test("끝난 뒤 늦게 온 만료는 버리고 완료는 한 번이다")
  func ignoresLateExpiration() async {
    let coordinator = Coordinator()

    let task = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    task.expire()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(coordinator.log.all.count { $0.hasPrefix("continuedCompleted") } == 1)
  }

  @Test("마무리 중에 요청하면 제출하지 않고 도는 중으로 답한다")
  func requestWhileFinishing() async {
    let indexingGate = Gate()
    let releaseGate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: indexingGate, releaseGate: releaseGate) })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    coordinator.impl.appDidEnterBackground()
    indexingGate.open()
    await waitUntil { coordinator.log.count("waitUntilStoreReleased") == 1 }

    #expect(coordinator.impl.continuedIndexingState == .active)
    #expect(coordinator.impl.requestContinuedIndexing(text: .test) == .started)
    #expect(coordinator.scheduler.continuedSubmissions.count == 1)
    releaseGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    #expect(coordinator.impl.continuedIndexingState == .idle)
  }

  @Test("분류가 끝을 알리기 전에 남은 일로 돌아오면(발열 양보 등) 처리 작업을 제출하고 실패로 끝낸다")
  func remainingWorkResubmits() async throws {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, result: IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
    })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(false)") == 1 }

    #expect(try #require(coordinator.log.index(of: "submit")) < coordinator.log.index(of: "continuedCompleted(false)")!)
  }

  @Test("실행에 넘긴 양보 확인이 발열 상태를 따른다")
  func shouldYieldFollowsThermalState() async {
    let gate = Gate()
    let indexing = IndexingDouble(log: EventLog(), gate: gate)
    let coordinator = Coordinator(log: EventLog(), indexing: { _ in indexing })

    _ = coordinator.launchContinued()
    await waitUntil { indexing.shouldYieldNow != nil }
    #expect(indexing.shouldYieldNow == false)
    coordinator.thermal.value = .serious
    #expect(indexing.shouldYieldNow == true)
    gate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("남은 일 없이 끝나면 앞에서는 제출 없이, 뒤에서는 제출하고 성공으로 끝낸다")
  func noRemainingWork() async {
    let front = Coordinator()
    _ = front.launchContinued()
    await waitUntil { front.log.count("continuedCompleted(true)") == 1 }
    #expect(front.log.count("submit") == 0)

    let gate = Gate()
    let back = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })
    _ = back.launchContinued()
    await waitUntil { back.log.count("runInBackground") == 1 }
    back.impl.appDidEnterBackground()
    gate.open()
    await waitUntil { back.log.count("continuedCompleted(true)") == 1 }
    #expect(back.log.count("submit") == 1)
  }

  @Test("진행률 없이 성공으로 끝나도 0/0 이 아니라 채운 막대로 끝낸다")
  func fillsBarWithoutProgress() async {
    let coordinator = Coordinator()

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.displayLog.last == "progress(1,1)")
  }

  @Test("저장소를 바꿨으면 완료 전에 위젯 갱신을 한 번 요청한다")
  func reloadsWidgetOnce() async throws {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, result: IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: true))
    })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.log.count("widget") == 1)
    #expect(try #require(coordinator.log.index(of: "widget")) < coordinator.log.index(of: "continuedCompleted(true)")!)
  }
}
