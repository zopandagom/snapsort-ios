import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 캡처 인박스 실패·훅·기록. 같은 동작은 `PhotoStoreCaptureInboxTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeCaptureInboxTests {
  private static let since = Date(timeIntervalSince1970: 1_700_000_000)

  private static func shot(_ id: String) -> IndexedImage {
    .stub(id: id, creationDate: self.since.addingTimeInterval(10), isScreenshot: true)
  }

  @Test("captureInboxErrors 는 그 번째 호출만 실패시키고 호출 수·인자는 실패한 호출도 기록한다")
  func errorsByCallIndex() async throws {
    let fake = PhotoStoreClientFake(images: [Self.shot("a")], captureInboxErrors: [0: .failed])
    let later = Self.since.addingTimeInterval(5)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.captureInboxScreenshots(createdSince: Self.since)
    }
    let retry = try await fake.captureInboxScreenshots(createdSince: later)

    #expect(retry.map(\.id) == ["a"])
    #expect(fake.captureInboxCallCount == 2)
    #expect(fake.captureInboxSinceArguments == [Self.since, later])
  }

  @Test("error 는 모든 호출을 실패시키고 호출 수를 세지 않으며 보관도 바꾸지 않는다")
  func globalErrorWins() async {
    let fake = PhotoStoreClientFake(images: [Self.shot("a")], error: .failed, captureInboxErrors: [0: .failed])

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.captureInboxScreenshots(createdSince: Self.since)
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.keepInCaptureInbox(id: "a")
    }
    #expect(fake.captureInboxCallCount == 0)
    #expect(fake.keptInCaptureInboxIDs.isEmpty)
  }

  @Test("captureInboxKeepError 는 보관만 실패시키고 아무것도 바꾸지 않는다")
  func keepErrorFailsOnlyKeep() async throws {
    let fake = PhotoStoreClientFake(images: [Self.shot("a")], captureInboxKeepError: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.keepInCaptureInbox(id: "a")
    }

    #expect(fake.keptInCaptureInboxIDs.isEmpty)
    #expect(fake.keepInCaptureInboxCount == 0)
    #expect(try await fake.captureInboxScreenshots(createdSince: Self.since).map(\.id) == ["a"])
  }

  @Test("처음 보관한 이미지는 있는 행만 남고, 보관 횟수는 true·false 모두 센다")
  func initialKeptAndCount() async throws {
    let fake = PhotoStoreClientFake(images: [Self.shot("a"), Self.shot("b")], keptInCaptureInbox: ["a", "gone"])

    #expect(fake.keptInCaptureInboxIDs == ["a"])
    #expect(try await fake.keepInCaptureInbox(id: "b"))
    #expect(try await fake.keepInCaptureInbox(id: "gone") == false)
    #expect(fake.keepInCaptureInboxCount == 2)
    #expect(fake.keptInCaptureInboxIDs == ["a", "b"])
  }

  @Test("onCaptureInboxScreenshots 는 결과를 계산한 뒤 기다리므로 그 사이에 바뀐 저장소는 반영되지 않는다")
  func hookReturnsEarlierResult() async throws {
    let (signal, release) = AsyncStream.makeStream(of: Void.self)
    let released = Task { for await _ in signal {} }
    let waiting = Mutex<[Int]>([])
    let fake = PhotoStoreClientFake(images: [Self.shot("a")], onCaptureInboxScreenshots: { index in
      waiting.withLock { $0.append(index) }
      await released.value
    })

    let read = Task { () -> [String]? in
      try? await fake.captureInboxScreenshots(createdSince: Self.since).map(\.id)
    }
    while waiting.withLock({ $0 }).isEmpty {
      await Task.yield()
    }
    try await fake.delete(ids: ["a"])
    release.finish()

    #expect(await read.value == ["a"])
    #expect(waiting.withLock { $0 } == [0])
  }

  @Test("onKeepInCaptureInbox 는 쓰기 전에 기다리고, 실패하는 호출에서도 호출 번호를 세어 부른다")
  func keepHookWaitsBeforeWrite() async throws {
    let (signal, release) = AsyncStream.makeStream(of: Void.self)
    let released = Task { for await _ in signal {} }
    let waiting = Mutex<[Int]>([])
    let fake = PhotoStoreClientFake(images: [Self.shot("a")], onKeepInCaptureInbox: { index in
      waiting.withLock { $0.append(index) }
      await released.value
    })
    let failingIndices = Mutex<[Int]>([])
    let failing = PhotoStoreClientFake(
      images: [Self.shot("a")],
      captureInboxKeepError: .failed,
      onKeepInCaptureInbox: { index in failingIndices.withLock { $0.append(index) } }
    )

    let keep = Task { try? await fake.keepInCaptureInbox(id: "a") }
    while waiting.withLock({ $0 }).isEmpty {
      await Task.yield()
    }
    #expect(fake.keptInCaptureInboxIDs.isEmpty)
    #expect(fake.keepInCaptureInboxCount == 0)
    release.finish()

    #expect(await keep.value == true)
    #expect(fake.keptInCaptureInboxIDs == ["a"])
    #expect(waiting.withLock { $0 } == [0])
    for _ in 0 ..< 2 {
      await #expect(throws: PhotoStoreError.failed) {
        try await failing.keepInCaptureInbox(id: "a")
      }
    }
    #expect(failingIndices.withLock { $0 } == [0, 1])
  }

  @Test("delete 는 보관 기록도 지우고 save 는 건드리지 않는다")
  func deleteClearsKept() async throws {
    let fake = PhotoStoreClientFake(images: [Self.shot("a"), Self.shot("b")], keptInCaptureInbox: ["a", "b"])

    try await fake.save([Self.shot("b")])
    try await fake.delete(ids: ["a"])

    #expect(fake.keptInCaptureInboxIDs == ["b"])
  }
}
