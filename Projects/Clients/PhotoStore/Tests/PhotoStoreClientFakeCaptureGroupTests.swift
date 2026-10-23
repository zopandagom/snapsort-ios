import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 캡처 묶음 실패·훅. 같은 동작은 `PhotoStoreCaptureGroupTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeCaptureGroupTests {
  @Test("captureGroupError 는 캡처 묶음 추출 대기·저장만 실패시키고 다른 호출은 성공한다")
  func captureGroupErrorFailsOnlyCaptureGroupExtraction() async throws {
    let fake = PhotoStoreClientFake(
      images: [CaptureGroupStoreFixture.image("a", .shopping, groups: nil)],
      captureGroupError: .failed
    )

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.captureGroupExtractionPendingIDs()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveCaptureGroups(["a": CaptureGroupStoreFixture.shopping])
    }
    #expect(fake.savedCaptureGroupBatches.isEmpty)
    #expect(fake.images.first?.captureGroups == nil)
    #expect(try await fake.captureGroupItems(in: .shopping).map(\.status) == [.checking])
    #expect(try await fake.receiptExtractionPendingIDs().isEmpty)
    try await fake.save([CaptureGroupStoreFixture.image("b", .shopping, groups: nil)])
    #expect(try await fake.indexedIDs() == ["a", "b"])
  }

  @Test("captureGroupSaveLimit 만큼 성공한 뒤 캡처 묶음 저장이 실패한다")
  func captureGroupSaveLimitFailsLaterSaves() async throws {
    let fake = PhotoStoreClientFake(
      images: [
        CaptureGroupStoreFixture.image("a", .shopping, groups: nil),
        CaptureGroupStoreFixture.image("b", .shopping, groups: nil),
      ],
      captureGroupSaveLimit: 1
    )

    try await fake.saveCaptureGroups(["a": CaptureGroupStoreFixture.shopping])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveCaptureGroups(["b": CaptureGroupStoreFixture.shopping])
    }

    #expect(fake.savedCaptureGroupBatches == [["a": CaptureGroupStoreFixture.shopping]])
    #expect(try await fake.captureGroupExtractionPendingIDs() == ["b"])
  }

  @Test("captureGroupItemsErrors 는 그 번째 목록 읽기만 실패시키고, onCaptureGroupItems 는 계산한 값을 늦게 돌려준다")
  func captureGroupItemsErrorsAndLateHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      captureGroupItemsErrors: [1: .failed],
      onCaptureGroupItems: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.save([CaptureGroupStoreFixture.image("a", .shopping, groups: nil)])
        }
      }
    )
    fake.set(instance)

    // 훅을 기다리는 동안 저장한 이미지는 이미 계산한 결과에 들지 않는다.
    #expect(try await instance.captureGroupItems(in: .shopping).isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await instance.captureGroupItems(in: .shopping)
    }
    #expect(try await instance.captureGroupItems(in: .shopping).map(\.id) == ["a"])
    #expect(indexes.withLock { $0 } == [0, 2])
    #expect(instance.captureGroupItemsCallCount == 3)
  }

  @Test("onSaveCaptureGroups 는 쓰기 전에 기다려, 그동안 지워진 행에는 쓰지 않는다")
  func onSaveCaptureGroupsRunsBeforeWriting() async throws {
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      images: [
        CaptureGroupStoreFixture.image("a", .shopping, groups: nil),
        CaptureGroupStoreFixture.image("b", .shopping, groups: nil),
      ],
      onSaveCaptureGroups: { _ in try? await fake.value?.delete(ids: ["a"]) }
    )
    fake.set(instance)

    try await instance.saveCaptureGroups([
      "a": CaptureGroupStoreFixture.shopping,
      "b": CaptureGroupStoreFixture.shopping,
    ])

    #expect(instance.images.map(\.id) == ["b"])
    #expect(instance.images.first?.captureGroups == CaptureGroupStoreFixture.shopping)
  }
}

/// 훅이 만들기 전의 대역을 참조하도록 나중에 채운다.
private final class Later<Value: Sendable>: Sendable {
  private let storage = Mutex<Value?>(nil)

  var value: Value? {
    self.storage.withLock { $0 }
  }

  func set(_ value: Value) {
    self.storage.withLock { $0 = value }
  }
}
