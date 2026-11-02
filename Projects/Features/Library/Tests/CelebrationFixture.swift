import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import PhotoStoreTesting
import Synchronization
import Testing
@testable import LibraryFeature

/// 분류 완료 축하의 머무는 시간을 테스트가 끝내는 수동 수면. 부른 시간을 기록하고 `resumeAll()` 까지 기다린다.
/// 부른 Task 가 취소되면 `CancellationError` 를 던진다(취소에 응답해야 화면 진입 Task 를 취소한 뒤 기다림이 끝난다).
final class ManualSleep: Sendable {
  private struct State {
    var durations: [Duration] = []
    var nextID = 0
    var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    /// continuation 을 받기 전에 취소된 수면.
    var cancelledEarly: Set<Int> = []
  }

  private let state = Mutex(State())

  /// 부른 시간을 부른 순서대로.
  var durations: [Duration] {
    self.state.withLock { $0.durations }
  }

  /// 지금 기다리는 수면 수.
  var waitingCount: Int {
    self.state.withLock { $0.waiters.count }
  }

  /// `LibraryModel(celebrationSleep:)` 에 넘길 클로저.
  var closure: @Sendable (Duration) async throws -> Void {
    { [self] duration in try await self.sleep(for: duration) }
  }

  func sleep(for duration: Duration) async throws {
    let id = self.state.withLock { state in
      state.durations.append(duration)
      defer { state.nextID += 1 }
      return state.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let isCancelled = self.state.withLock { state in
          if state.cancelledEarly.remove(id) != nil {
            return true
          }
          state.waiters[id] = continuation
          return false
        }
        if isCancelled {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let continuation = self.state.withLock { state -> CheckedContinuation<Void, any Error>? in
        guard let continuation = state.waiters.removeValue(forKey: id) else {
          state.cancelledEarly.insert(id)
          return nil
        }
        return continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  /// 기다리는 수면을 모두 깨운다(머무는 시간이 지났다).
  func resumeAll() {
    let waiters = self.state.withLock { state in
      defer { state.waiters = [:] }
      return Array(state.waiters.values)
    }
    waiters.forEach { $0.resume() }
  }
}

/// 축하 테스트의 Model 과 대역. 인덱서는 구독을 끝낼 때까지 이어지고, 수면은 `ManualSleep` 이다.
@MainActor
struct CelebrationFixture {
  let model: LibraryModel
  let photoLibrary: PhotoLibraryClientFake
  let indexing: IndexingClientFake
  let photoStore: PhotoStoreClientFake
  let sleep: ManualSleep

  init(hasIndexer: Bool = true) {
    self.indexing = IndexingClientFake(finishesAfterProgress: false)
    self.photoStore = PhotoStoreClientFake()
    self.sleep = ManualSleep()
    self.photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    self.model = libraryModel(
      self.photoLibrary,
      indexing: hasIndexer ? self.indexing : nil,
      photoStore: self.photoStore,
      celebrationSleep: self.sleep.closure
    )
  }

  /// 화면 진입을 시작하고 인덱서 실행 `runCount` 번째가 구독될 때까지 기다린다.
  func appear(runCount: Int = 1) async -> Task<Void, Never> {
    let appear = Task { await self.model.onAppear() }
    await self.waitForRun(runCount)
    return appear
  }

  /// 인덱서 실행 `count` 번째가 구독될 때까지 기다린다.
  func waitForRun(_ count: Int) async {
    await waitUntil { self.indexing.runCount == count && self.indexing.activeRunCount == 1 }
  }

  /// 진행률을 보내고 Model 이 받아 반영할 때까지 기다린다. 같은 값을 다시 보내도 받은 것을 알도록 저장소 변경 번호로 본다.
  func send(_ progress: IndexingProgress) async {
    let revision = self.model.storeRevision
    self.indexing.sendProgress(progress)
    await waitUntil { self.model.storeRevision > revision }
  }

  /// 인덱서 스트림을 끝내 멈춤이 될 때까지 기다린다.
  func stop() async {
    self.indexing.finishRuns()
    await waitUntil { self.model.isIndexingStopped }
  }

  /// 축하가 보이고 머무는 시간을 재기 시작할 때까지 기다린다.
  func waitForCelebration() async {
    await waitUntil { self.model.indexingCelebration != nil && self.sleep.waitingCount == 1 }
  }
}

extension IndexingProgress {
  /// 축하 테스트용 줄임. 수는 `IndexingProgress.init` 과 같은 순서다.
  static func celebration(
    total: Int,
    indexed: Int,
    skipped: Int = 0,
    pending: Int = 0,
    recognized: Int = 0,
    skippedText: Int = 0
  ) -> IndexingProgress {
    IndexingProgress(
      totalCount: total,
      indexedCount: indexed,
      skippedCount: skipped,
      pendingTextCount: pending,
      recognizedTextCount: recognized,
      skippedTextCount: skippedText
    )
  }
}
