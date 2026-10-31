import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import Testing
import TripPlaceInterface
@testable import BackgroundIndexingImpl

/// 계속 처리 작업의 장소 구간: 분류·글자 읽기 끝 뒤 미리 받기 회차가 끝날 때까지의 진행 표시·만료·회차 2·앞뒤 전이 (설계 R2-7).
@MainActor
struct BackgroundIndexingContinuedPlaceTests {
  @Test("회차 진행은 글자 읽기 중에는 막대만, 끝 뒤에는 장소 단계 문구와 막대를 바꾸고 회차 끝에 못 한 키를 뺀다")
  func showsPlaceProgress() async {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.tripPlace?.sendPrefetchProgress(.init(doneCount: 0, totalCount: 3))
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    coordinator.tripPlace?.sendPrefetchProgress(.init(doneCount: 1, totalCount: 3))
    await waitUntil { coordinator.displayLog.contains("title(fetchingPlaceNames,1/3)") }
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.displayLog == [
      "progress(0,0)",
      "progress(0,3)", "title(recognizingText,0/3)",
      // 회차 시작·(0,3): 글자 읽기 중이라 문구는 그대로이고 막대만 는다.
      "progress(0,3)",
      "progress(0,6)",
      // 끝: hold 를 놓고 장소 단계로.
      "progress(3,6)", "title(fetchingPlaceNames,0/3)",
      "progress(4,6)", "title(fetchingPlaceNames,1/3)",
      // 회차 끝: 못 한 키 2개를 뺀다.
      "progress(4,4)",
      // 성공 끝 표시.
      "progress(4,4)",
    ])
    #expect(coordinator.log.count("prefetch.cancelled") == 0)
  }

  @Test("회차가 알리기 전에 끝을 받으면 장소 단계를 0·0 으로 보인다")
  func showsPlaceStageBeforeFirstReport() async {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.displayLog.contains("title(fetchingPlaceNames,0/0)") }
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("장소 구간에 만료(사용자 취소)되면 회차를 취소하고 손 뗀 뒤 처리 작업을 제출하고 실패로 끝낸다")
  func expirationDuringPlaceStage() async throws {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    let task = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.impl.appDidEnterBackground()
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    task.expire()
    await waitUntil { coordinator.log.count("continuedCompleted(false)") == 1 }

    let log = coordinator.log
    let prefetchCancelled = try #require(log.index(of: "prefetch.cancelled"))
    let hold = try #require(log.index(of: "hold"))
    let wait = try #require(log.all.lastIndex(of: "waitUntilStoreReleased"))
    let submit = try #require(log.index(of: "submit"))
    let completed = try #require(log.index(of: "continuedCompleted(false)"))
    #expect(prefetchCancelled < hold)
    #expect(hold < wait)
    #expect(wait < submit)
    #expect(submit < completed)
    #expect(log.count("prefetch") == 1)
  }

  @Test("회차 1 이 알리지 않고 돌아왔고 끝을 받았고 뒤면 회차를 한 번 더 열고, 그 진행도 보인다")
  func secondRoundInBackground() async {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: {
        TripPlaceDouble(log: $0, rounds: [
          .init(gate: tripGate),
          .init(progress: [.init(doneCount: 0, totalCount: 2), .init(doneCount: 2, totalCount: 2)]),
        ])
      }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.impl.appDidEnterBackground()
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.log.count("prefetch") == 2)
    #expect(coordinator.displayLog.contains("title(fetchingPlaceNames,2/2)"))
    #expect(coordinator.log.count("submit") == 1)
  }

  @Test("앞이면 회차를 다시 열지 않는다")
  func noSecondRoundInForeground() async {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.log.count("prefetch") == 1)
  }

  @Test("회차 1 이 진행을 알렸으면 회차를 다시 열지 않는다")
  func noSecondRoundAfterReport() async {
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

    #expect(coordinator.log.count("prefetch") == 1)
  }

  @Test("끝을 받기 전에 분류가 남은 일로 돌아오면 회차를 다시 열지 않고 처리 작업을 제출하고 실패로 끝낸다")
  func noSecondRoundWithoutFinish() async {
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: {
        IndexingDouble(
          log: $0,
          progress: [.recognizingText],
          result: IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false)
        )
      },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.impl.appDidEnterBackground()
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(false)") == 1 }

    #expect(coordinator.log.count("prefetch") == 1)
    #expect(coordinator.log.count("submit") == 1)
  }

  @Test("장소 구간에 앱이 앞으로 오면 실행기를 다시 쥐지 않고, 회차가 끝나면 제출 없이 성공으로 끝낸다")
  func foregroundDuringPlaceStage() async {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.impl.appDidEnterBackground()
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    coordinator.impl.appDidBecomeActive()
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.log.count("activity(true)") == 1)
    #expect(coordinator.log.count("runInBackground") == 1)
    #expect(coordinator.log.count("submit") == 0)
    #expect(!coordinator.log.all.contains { $0.hasPrefix("begin") })
  }

  @Test("장소 구간에 다시 뒤로 가도 시간을 빌리거나 제출하지 않고, 끝에서 처리 작업을 제출한다")
  func backgroundAgainDuringPlaceStage() async throws {
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
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    coordinator.impl.appDidEnterBackground()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!coordinator.log.all.contains { $0.hasPrefix("begin") })
    #expect(coordinator.log.count("submit") == 0)

    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    #expect(try #require(coordinator.log.index(of: "submit")) < coordinator.log.index(of: "continuedCompleted(true)")!)
  }

  @Test("hold 를 걸자마자 받은 첫 진행률이 끝이어도 hold 를 놓고 회차가 끝난 뒤 성공으로 끝낸다")
  func firstProgressFinished() async {
    let indexingGate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, progress: [.finished], gate: indexingGate) })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.log.count("runInBackground.cancelled") == 1)
    #expect(coordinator.log.count("prefetch") == 1)
  }
}
