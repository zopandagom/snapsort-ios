import Core
import PhotoLibraryInterface
import PhotoLibraryTesting
import Synchronization
import Testing

struct PhotoLibraryClientFakeDeletionTests {
  private static func fake(
    ids: [String] = ["a", "b", "c"],
    accessState: PhotoAccessState = .authorized,
    deletionErrors: [Int: ImageDeletionError] = [:],
    deletionGate: (@Sendable (Set<ImageAsset.ID>) async -> Void)? = nil
  ) -> PhotoLibraryClientFake {
    PhotoLibraryClientFake(
      currentState: accessState,
      imageAssets: ids.map { .stub(id: $0) },
      deletionErrors: deletionErrors,
      deletionGate: deletionGate
    )
  }

  @Test("보관함에 있는 것은 지우고 없는 것은 건너뛴 것으로 돌려준다")
  func deletesAndSkips() async throws {
    let fake = Self.fake()

    let result = try await fake.deleteImages(ids: ["a", "gone"])

    #expect(result == ImageDeletionResult(deletedIDs: ["a"], skippedIDs: ["gone"]))
    #expect(await fake.fetchImageAssets().map(\.id) == ["b", "c"])
  }

  @Test("지우면 구독자에게 삭제를 한 번 알린다")
  func sendsOneRemovalChange() async throws {
    let fake = Self.fake()
    let changes = await fake.imageChanges()
    var iterator = changes.makeAsyncIterator()

    _ = try await fake.deleteImages(ids: ["c", "a"])

    #expect(await iterator.next() == .incremental(inserted: [], removed: ["a", "c"]))
  }

  @Test("지운 것이 없으면 알리지 않는다")
  func skippedOnlyDoesNotNotify() async throws {
    let fake = Self.fake()
    let changes = await fake.imageChanges()
    var iterator = changes.makeAsyncIterator()

    let result = try await fake.deleteImages(ids: ["gone"])
    fake.finishImageChanges()

    #expect(result.deletedIDs.isEmpty)
    #expect(await iterator.next() == nil)
  }

  @Test("정해 둔 호출 번호의 실패는 조회 결과를 바꾸지 않고 다른 호출은 성공한다")
  func failsOnlyConfiguredCall() async throws {
    let fake = Self.fake(deletionErrors: [0: .failed])

    await #expect(throws: ImageDeletionError.failed) {
      try await fake.deleteImages(ids: ["a"])
    }
    #expect(await fake.fetchImageAssets().map(\.id) == ["a", "b", "c"])
    let retry = try await fake.deleteImages(ids: ["a"])

    #expect(retry.deletedIDs == ["a"])
    #expect(fake.deletionRequests == [["a"], ["a"]])
  }

  @Test("사용자 취소를 정해 두면 아무것도 지우지 않는다")
  func userCancelled() async {
    let fake = Self.fake(deletionErrors: [0: .userCancelled])

    await #expect(throws: ImageDeletionError.userCancelled) {
      try await fake.deleteImages(ids: ["a", "b"])
    }
    #expect(await fake.fetchImageAssets().count == 3)
  }

  @Test("읽기 권한이 없으면 notAuthorized 를 던지고 요청은 기록한다", arguments: [PhotoAccessState.denied, .notDetermined])
  func notAuthorized(state: PhotoAccessState) async {
    let fake = Self.fake(accessState: state)

    await #expect(throws: ImageDeletionError.notAuthorized) {
      try await fake.deleteImages(ids: ["a"])
    }
    #expect(fake.deletionRequests == [["a"]])
    #expect(await fake.fetchImageAssets().count == 3)
  }

  @Test("제한 접근에서도 지울 수 있다")
  func limitedAccessDeletes() async throws {
    let fake = Self.fake(accessState: .limited)

    #expect(try await fake.deleteImages(ids: ["b"]).deletedIDs == ["b"])
  }

  @Test("대기를 주면 요청을 기록한 뒤 식별자를 넘겨 기다리고, 풀린 뒤에 결과를 준다")
  func waitsForDeletionGate() async {
    let (signal, release) = AsyncStream.makeStream(of: Void.self)
    let released = Task { for await _ in signal {} }
    let waiting = Mutex<[Set<ImageAsset.ID>]>([])
    let fake = Self.fake(deletionGate: { ids in
      waiting.withLock { $0.append(ids) }
      await released.value
    })

    let deletion = Task { () -> Set<ImageAsset.ID>? in
      try? await fake.deleteImages(ids: ["a"]).deletedIDs
    }
    while waiting.withLock({ $0 }).isEmpty {
      await Task.yield()
    }
    #expect(fake.deletionRequests == [["a"]])
    #expect(await fake.fetchImageAssets().count == 3)
    release.finish()

    #expect(await deletion.value == ["a"])
    #expect(await fake.fetchImageAssets().count == 2)
  }

  @Test("호출한 Task 가 취소돼도 결과를 돌려준다")
  func ignoresTaskCancellation() async {
    let fake = Self.fake()

    let deletion = Task { () -> Set<ImageAsset.ID>? in
      withUnsafeCurrentTask { $0?.cancel() }
      return try? await fake.deleteImages(ids: ["a"]).deletedIDs
    }

    #expect(await deletion.value == ["a"])
  }
}
