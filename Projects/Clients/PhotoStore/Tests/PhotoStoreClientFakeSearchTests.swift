import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 검색 목록 실패·훅. 같은 동작은 `PhotoStoreSearchTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeSearchTests {
  @Test("searchEntriesErrors 는 그 번째 읽기만 실패시키고 호출 수에는 실패한 호출도 센다")
  func errorsByCallIndex() async throws {
    let fake = PhotoStoreClientFake(
      images: [CaptureGroupStoreFixture.image("a", .shopping, groups: nil)],
      searchEntriesErrors: [1: .failed]
    )

    #expect(try await fake.searchEntries().entries.map(\.id) == ["a"])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.searchEntries()
    }
    #expect(try await fake.searchEntries().entries.map(\.id) == ["a"])
    #expect(fake.searchEntriesCallCount == 3)
  }

  @Test("error 로 던진 호출은 호출 수에 세지 않는다")
  func globalErrorIsNotCounted() async {
    let fake = PhotoStoreClientFake(error: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.searchEntries()
    }
    #expect(fake.searchEntriesCallCount == 0)
  }

  @Test("onSearchEntries 는 계산한 뒤 기다리므로 기다리는 동안 저장해도 앞서 계산한 값을 돌려준다")
  func hookWaitsAfterComputing() async throws {
    let indexes = Mutex<[Int]>([])
    let later = Later<PhotoStoreClientFake>()
    let fake = PhotoStoreClientFake(
      onSearchEntries: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await later.value?.save([CaptureGroupStoreFixture.image("a", .shopping, groups: nil)])
        }
      }
    )
    later.set(fake)

    #expect(try await fake.searchEntries().entries.isEmpty)
    #expect(try await fake.searchEntries().entries.map(\.id) == ["a"])
    #expect(indexes.withLock { $0 } == [0, 1])
  }

  @Test("실패하는 호출에서는 훅을 부르지 않는다")
  func hookSkippedOnFailure() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = PhotoStoreClientFake(
      searchEntriesErrors: [0: .failed],
      onSearchEntries: { index in indexes.withLock { $0.append(index) } }
    )

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.searchEntries()
    }
    _ = try await fake.searchEntries()

    #expect(indexes.withLock { $0 } == [1])
  }
}

private final class Later<Value: Sendable>: Sendable {
  private let storage = Mutex<Value?>(nil)

  var value: Value? {
    self.storage.withLock { $0 }
  }

  func set(_ value: Value) {
    self.storage.withLock { $0 = value }
  }
}
