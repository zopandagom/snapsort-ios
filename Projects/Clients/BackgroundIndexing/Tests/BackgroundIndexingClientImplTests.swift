import Foundation
import IndexingInterface
import Testing
@testable import BackgroundIndexingImpl

@MainActor
struct BackgroundIndexingClientImplTests {
  // MARK: - 등록

  @Test("식별자로 한 번만 등록하고, 두 번 불러도 다시 등록하지 않는다")
  func registersOnce() {
    let coordinator = Coordinator()

    coordinator.impl.registerLaunchHandler()
    coordinator.impl.registerLaunchHandler()

    #expect(coordinator.scheduler.registeredIdentifiers == [Coordinator.identifier])
  }

  @Test("식별자가 없으면 등록하지 않는다")
  func skipsRegistrationWithoutIdentifier() {
    let coordinator = Coordinator(taskIdentifier: nil)

    coordinator.impl.registerLaunchHandler()

    #expect(coordinator.scheduler.registeredIdentifiers.isEmpty)
  }

  // MARK: - 작업 끝

  @Test("저장소를 바꾸고 할 일 없이 끝나면 위젯 갱신 한 번, 제출 없이 성공으로 완료한다")
  func completesAfterChangingStore() async throws {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, result: IndexingBackgroundResult(hasRemainingWork: false, didChangeStore: true))
    })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(coordinator.log.count("widget") == 1)
    #expect(coordinator.scheduler.submissions.isEmpty)
    #expect(try #require(coordinator.log.index(of: "widget")) < coordinator.log.index(of: "completed(true)")!)
  }

  @Test("저장소를 바꾸지 않았으면 위젯 갱신을 요청하지 않는다")
  func skipsWidgetWithoutChange() async {
    let coordinator = Coordinator()

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(coordinator.log.count("widget") == 0)
  }

  @Test("할 일이 남으면 완료보다 먼저 다시 제출한다")
  func resubmitsBeforeCompletionWhenWorkRemains() async throws {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, result: IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
    })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(try #require(coordinator.log.index(of: "submit")) < coordinator.log.index(of: "completed(true)")!)
  }

  @Test("만료되면 실행·회차를 취소하고 저장소에서 손 뗀 뒤 다시 제출하고 실패로 한 번 완료한다")
  func expirationOrder() async throws {
    let indexingGate = Gate()
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText], gate: indexingGate) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) },
      isActive: false
    )

    let task = coordinator.launch()
    await waitUntil { coordinator.log.count("prefetch") == 1 && coordinator.log.count("runInBackground") == 1 }
    task.expire()
    task.expire()
    await waitUntil { coordinator.log.count("completed(false)") == 1 }

    let log = coordinator.log
    let cancelled = try #require(log.index(of: "runInBackground.cancelled"))
    let prefetchCancelled = try #require(log.index(of: "prefetch.cancelled"))
    // 시작 때 막음 적용(앱이 뒤에 있음)이 아니라 작업 끝의 막음을 본다.
    let hold = try #require(log.all.lastIndex(of: "hold"))
    let wait = try #require(log.all.lastIndex(of: "waitUntilStoreReleased"))
    let submit = try #require(log.index(of: "submit"))
    let completed = try #require(log.index(of: "completed(false)"))
    #expect(cancelled < hold)
    #expect(prefetchCancelled < hold)
    #expect(hold < wait)
    #expect(wait < submit)
    #expect(submit < completed)
    #expect(log.count("completed(false)") == 1)
    #expect(log.count("completed(true)") == 0)
  }

  @Test("요청은 충전 중에만, 네트워크 조건 없이 같은 식별자로 낸다")
  func requestAttributes() async {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, result: IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
    })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(coordinator.scheduler.submissions == [
      SchedulerDouble.Submission(
        identifier: Coordinator.identifier,
        requiresExternalPower: true,
        requiresNetworkConnectivity: false
      ),
    ])
  }

  // MARK: - 발열

  @Test("시작 때 기기가 뜨거우면 분류하지 않고 다시 제출한 뒤 완료한다")
  func skipsWhenHotAtStart() throws {
    let coordinator = Coordinator()
    coordinator.thermal.value = .serious

    _ = coordinator.launch()

    #expect(coordinator.log.count("runInBackground") == 0)
    #expect(try #require(coordinator.log.index(of: "submit")) < coordinator.log.index(of: "completed(true)")!)
  }

  @Test("실행에 넘긴 양보 확인이 발열 상태를 따른다")
  func shouldYieldFollowsThermalState() async {
    let gate = Gate()
    let indexing = IndexingDouble(log: EventLog(), gate: gate)
    let coordinator = Coordinator(log: EventLog(), indexing: { _ in indexing })

    _ = coordinator.launch()
    await waitUntil { indexing.shouldYieldNow != nil }
    #expect(indexing.shouldYieldNow == false)
    coordinator.thermal.value = .critical
    #expect(indexing.shouldYieldNow == true)
    coordinator.thermal.value = .fair
    #expect(indexing.shouldYieldNow == false)
    gate.open()
  }

  // MARK: - 미리 받기

  @Test("1단계 진행률만 오면 미리 받기를 하지 않는다")
  func skipsPrefetchWhileClassifying() async {
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, progress: [.classifying]) })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(coordinator.log.count("prefetch") == 0)
  }

  @Test("1단계를 마친 진행률이 오면 미리 받기 회차를 한 번 돌린다")
  func prefetchesOnceAfterClassification() async throws {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, progress: [.classifying, .recognizingText, .recognizingText])
    })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(coordinator.log.count("prefetch") == 1)
    #expect(try #require(coordinator.log.index(of: "prefetch")) < coordinator.log.index(of: "completed(true)")!)
  }

  @Test("분류가 먼저 끝나도 미리 받기 회차가 끝난 뒤에 완료한다")
  func waitsForPrefetchBeforeCompletion() async {
    let tripGate = Gate()
    let coordinator = Coordinator(
      indexing: { IndexingDouble(log: $0, progress: [.recognizingText]) },
      tripPlace: { TripPlaceDouble(log: $0, gate: tripGate) }
    )

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("prefetch") == 1 }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(coordinator.log.count("completed(true)") == 0)
    tripGate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
  }

  // MARK: - 저장소 없음·제출 실패

  @Test("인덱서가 없으면 바로 다시 제출하고 실패로 완료한다")
  func completesWithoutIndexing() {
    let coordinator = Coordinator(indexing: { _ in nil })

    _ = coordinator.launch()

    #expect(coordinator.log.all == ["submit", "completed(false)"])
  }

  @Test("제출이 실패해도 완료를 알린다")
  func completesWhenSubmitThrows() async {
    let coordinator = Coordinator(indexing: {
      IndexingDouble(log: $0, result: IndexingBackgroundResult(hasRemainingWork: true, didChangeStore: false))
    })
    coordinator.scheduler.submitError = CocoaError(.featureUnsupported)

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }

    #expect(coordinator.log.count("submit") == 1)
  }

  @Test("도는 작업이 있는데 또 오면 뒤 작업을 바로 실패로 완료한다")
  func completesDuplicateTaskImmediately() async {
    let gate = Gate()
    let coordinator = Coordinator(indexing: { IndexingDouble(log: $0, gate: gate) })

    _ = coordinator.launch()
    await waitUntil { coordinator.log.count("runInBackground") == 1 }
    let duplicate = TaskDouble(log: coordinator.log)
    coordinator.scheduler.launch(duplicate)

    #expect(coordinator.log.count("completed(false)") == 1)
    #expect(coordinator.log.count("runInBackground") == 1)
    gate.open()
    await waitUntil { coordinator.log.count("completed(true)") == 1 }
  }
}
