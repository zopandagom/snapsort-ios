import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 특징 벡터·비슷한 사진 실패·훅·기록. 같은 동작은 `PhotoStoreSimilarPhotoTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeSimilarPhotoTests {
  private typealias Fixture = SimilarPhotoStoreFixture

  @Test("similarPhotoEntriesErrors 는 그 번째 읽기만 실패시키고 호출 수에는 실패한 호출도 센다")
  func errorsByCallIndex() async throws {
    let fake = PhotoStoreClientFake(
      images: [Fixture.photo("a", seconds: 0), Fixture.photo("b", seconds: 1)],
      similarPhotoEntriesErrors: [1: .failed]
    )

    #expect(try await fake.similarPhotoEntries().photos.map(\.id) == ["a", "b"])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.similarPhotoEntries()
    }
    #expect(try await fake.similarPhotoEntries().photos.map(\.id) == ["a", "b"])
    #expect(fake.similarPhotoEntriesCallCount == 3)
  }

  @Test("onSimilarPhotoEntries 는 계산한 뒤 기다리므로 기다리는 동안 저장해도 앞서 계산한 값을 돌려준다")
  func hookWaitsAfterComputing() async throws {
    let indexes = Mutex<[Int]>([])
    let later = Later<PhotoStoreClientFake>()
    let fake = PhotoStoreClientFake(
      images: [Fixture.photo("a", seconds: 0)],
      onSimilarPhotoEntries: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await later.value?.save([Fixture.photo("b", seconds: 1)])
        }
      }
    )
    later.set(fake)

    #expect(try await fake.similarPhotoEntries().photos.isEmpty)
    #expect(try await fake.similarPhotoEntries().photos.map(\.id) == ["a", "b"])
    #expect(indexes.withLock { $0 } == [0, 1])
  }

  @Test("featurePrintError 는 대기 조회·벡터 저장만 실패시키고 벡터를 바꾸지 않는다. 대기 조회 수는 실패도 센다")
  func featurePrintError() async throws {
    let fake = PhotoStoreClientFake(images: [Fixture.photo("a", x: nil)], featurePrintError: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.featurePrintPendingIDs()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveFeaturePrints(["a": Fixture.featurePrint(0)])
    }
    #expect(fake.images.first?.featurePrint == nil)
    #expect(fake.savedFeaturePrintBatches.isEmpty)
    #expect(fake.featurePrintPendingIDsCallCount == 1)
    #expect(try await fake.similarPhotoEntries().uncomparedCount == 1)
  }

  @Test("featurePrintSaveLimit 만큼 저장한 뒤부터 벡터 저장이 실패하고 기록에는 성공한 호출만 남는다")
  func saveLimit() async throws {
    let fake = PhotoStoreClientFake(
      images: [Fixture.photo("a", x: nil), Fixture.photo("b", x: nil)],
      featurePrintSaveLimit: 1
    )

    try await fake.saveFeaturePrints(["a": Fixture.featurePrint(0)])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveFeaturePrints(["b": Fixture.featurePrint(0)])
    }

    #expect(fake.savedFeaturePrintBatches == [["a": Fixture.featurePrint(0)]])
    #expect(try await fake.featurePrintPendingIDs() == ["b"])
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
