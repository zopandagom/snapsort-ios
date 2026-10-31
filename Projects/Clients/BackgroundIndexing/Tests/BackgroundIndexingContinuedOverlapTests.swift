import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import Testing
@testable import BackgroundIndexingImpl

/// 처리 작업(`BGProcessingTask`)과 계속 처리 작업이 겹칠 때 (설계 §4.3-8, §11.1-13·14·19·25·26).
@MainActor
struct BackgroundIndexingContinuedOverlapTests {
  @Test("처리 작업이 도는 중 계속 처리가 시작하면 둘 다 실행기를 쥐고, 뒤로 가도 빌리거나 제출하지 않으며 처리 작업이 끝나도 손 떼지 않는다")
  func continuedStartsDuringProcessing() async {
    let processingGate = Gate()
    let continuedGate = Gate()
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, calls: [.init(gate: processingGate), .init(gate: continuedGate)])
    })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground") == 2 }
    coordinator.impl.appDidEnterBackground()
    processingGate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
    try? await Task.sleep(for: .milliseconds(50))

    #expect(!coordinator.log.all.contains { $0.hasPrefix("begin") })
    #expect(coordinator.log.count("submit") == 0)
    #expect(coordinator.log.count("hold") == 0)

    continuedGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    #expect(coordinator.log.count("hold") == 1)
    #expect(coordinator.log.count("submit") == 1)
  }

  @Test("계속 처리가 도는 중 처리 작업이 오면 바로 실패로 끝내고 실행기를 다시 쥐지 않는다")
  func processingDuringContinuedCompletesImmediately() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    _ = coordinator.launch()

    #expect(coordinator.log.count("completed(false)") == 1)
    #expect(coordinator.log.count("runInBackground") == 1)
    gate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("장소 구간에 처리 작업이 와도 바로 실패로 끝낸다")
  func processingDuringPlaceStageCompletesImmediately() async {
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
    _ = coordinator.launch()

    #expect(coordinator.log.count("completed(false)") == 1)
    #expect(coordinator.log.count("runInBackground") == 1)
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
  }

  @Test("둘 다 쥔 채 뒤에서 계속 처리가 먼저 끝나면 저장소를 연 채 두고, 처리 작업이 끝날 때 손 뗀다")
  func continuedFinishesFirstWhileProcessingHolds() async throws {
    let processingGate = Gate()
    let continuedGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: {
        IndexingDouble(log: $0, calls: [
          .init(gate: processingGate),
          .init(progress: [.recognizingText, .finished], gate: continuedGate),
        ])
      },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.impl.appDidEnterBackground()
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(coordinator.log.count("hold") == 0)

    processingGate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
    #expect(try #require(coordinator.log.index(of: "hold")) < coordinator.log.index(of: "completed(true)")!)
  }

  @Test("처리 작업은 끝 진행률에도 실행기를 놓지 않고 회차를 한 번 돌린다")
  func processingKeepsHoldingAfterFinished() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, progress: [.recognizingText, .finished], gate: gate)
    })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(coordinator.log.count("runInBackground.cancelled") == 0)

    gate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
    #expect(coordinator.log.count("prefetch") == 1)
  }
}
