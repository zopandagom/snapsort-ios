import BackgroundIndexingInterface
import Foundation
import IndexingInterface
import Testing
import TripPlaceInterface
@testable import BackgroundIndexingImpl

/// 계속 처리 작업의 진행 표시를 기본 무게(`.default`)로 본다: 글자 읽기 장마다 신호, 단계 경계, 장소 회차 예약 (설계 R7-6.2 C1·C2, R7 반영 1 C4).
@MainActor
struct BackgroundIndexingContinuedWeightTests {
  @Test("글자 읽기 단계에서 장마다 신호가 오면 막대가 200 씩, 부제가 장마다 오른다")
  func perImageTextProgress() async {
    let gate = Gate()
    let coordinator = Coordinator(
      indexing: {
        IndexingDouble(log: $0, progress: [.recognizingText, Self.text(1), Self.text(2), .finished], gate: gate)
      },
      tripPlace: { _ in nil },
      meterWeights: .default
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.displayLog == [
      "progress(0,0)",
      "progress(0,600)", "title(recognizingText,0/3)",
      "progress(200,600)", "title(recognizingText,1/3)",
      "progress(400,600)", "title(recognizingText,2/3)",
      "progress(600,600)",
      "progress(600,600)",
    ])
  }

  @Test("1단계 마지막 값에서 2단계 첫 값으로 넘어갈 때 완료가 줄지 않고 전체는 완료 이상이다")
  func stageChangeKeepsCompleted() async throws {
    let gate = Gate()
    let coordinator = Coordinator(
      indexing: {
        IndexingDouble(
          log: $0,
          progress: [
            IndexingProgress(totalCount: 10, indexedCount: 5, skippedCount: 0),
            IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, pendingTextCount: 3),
            .finished,
          ],
          gate: gate
        )
      },
      tripPlace: { _ in nil },
      meterWeights: .default
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    let values = try Self.progressValues(coordinator.displayLog)
    #expect(values.count == 5)
    var previous: Int64 = 0
    for (completed, total) in values.dropFirst() {
      #expect(completed >= previous)
      #expect(total >= completed)
      previous = completed
    }
    #expect(coordinator.displayLog.contains("title(recognizingText,0/3)"))
  }

  @Test("미리 받기가 있으면 회차 몫을 미리 넣어, 회차가 키 수를 알릴 때 막대 전체가 늘지 않는다")
  func placeRoundDoesNotGrowTotal() async throws {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) },
      meterWeights: .default
    )

    _ = coordinator.launchContinued()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    coordinator.tripPlace?.sendPrefetchProgress(.init(doneCount: 0, totalCount: 3))
    coordinator.indexing?.sendProgress(.finished)
    await waitUntil { coordinator.log.count("runInBackground.cancelled") == 1 }
    tripGate.open()
    await waitUntil { coordinator.log.count("continuedCompleted(true)") == 1 }

    #expect(coordinator.displayLog == [
      "progress(0,0)",
      // 대기 3장 × 200 + 회차 예약 30키 × 350.
      "progress(0,11100)", "title(recognizingText,0/3)",
      // 회차 시작.
      "progress(0,11100)",
      // (0,3): 예약을 그 회차의 3키로 바꾼다.
      "progress(0,1650)",
      "progress(600,1650)", "title(fetchingPlaceNames,0/3)",
      // 회차 끝: 못 한 키 3개 몫이 빠진다.
      "progress(600,600)",
      "progress(600,600)",
    ])
    let totals = try Self.progressValues(coordinator.displayLog).dropFirst().map(\.1)
    #expect(zip(totals, totals.dropFirst()).allSatisfy { $0 >= $1 })
  }

  /// `recognizingText` 다음 글자 `done` 장 읽음(대기 3 − done).
  private static func text(_ done: Int) -> IndexingProgress {
    IndexingProgress(
      totalCount: 10,
      indexedCount: 10,
      skippedCount: 0,
      pendingTextCount: 3 - done,
      recognizedTextCount: done
    )
  }

  /// 진행 표시 기록의 `progress(완료,전체)` 값들.
  private static func progressValues(_ log: [String]) throws -> [(Int64, Int64)] {
    try log.filter { $0.hasPrefix("progress(") }.map { entry in
      let numbers = entry.dropFirst("progress(".count).dropLast().split(separator: ",")
      return try (#require(Int64(numbers[0])), #require(Int64(numbers[1])))
    }
  }
}
