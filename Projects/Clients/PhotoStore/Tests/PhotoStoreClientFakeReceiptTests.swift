import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 영수증 실패·훅. 같은 동작은 `PhotoStoreReceiptTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeReceiptTests {
  @Test("receiptError 는 영수증 추출 대기·저장만 실패시키고 다른 호출은 성공한다")
  func receiptErrorFailsOnlyReceiptExtraction() async throws {
    let fake = PhotoStoreClientFake(images: [ReceiptStoreFixture.receipt("a", info: nil)], receiptError: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.receiptExtractionPendingIDs()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveReceipts(["a": ReceiptStoreFixture.found])
    }
    #expect(fake.savedReceiptBatches.isEmpty)
    #expect(fake.images.first?.receipt == nil)
    #expect(try await fake.receipts().map(\.status) == [.checking])
    #expect(try await fake.gifticonExtractionPendingIDs().isEmpty)
    try await fake.save([ReceiptStoreFixture.receipt("b")])
    #expect(try await fake.indexedIDs() == ["a", "b"])
  }

  @Test("receiptSaveLimit 만큼 성공한 뒤 영수증 저장이 실패한다")
  func receiptSaveLimitFailsLaterSaves() async throws {
    let fake = PhotoStoreClientFake(
      images: [ReceiptStoreFixture.receipt("a", info: nil), ReceiptStoreFixture.receipt("b", info: nil)],
      receiptSaveLimit: 1
    )

    try await fake.saveReceipts(["a": ReceiptStoreFixture.found])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveReceipts(["b": ReceiptStoreFixture.found])
    }

    #expect(fake.savedReceiptBatches == [["a": ReceiptStoreFixture.found]])
    #expect(try await fake.receiptExtractionPendingIDs() == ["b"])
  }

  @Test("receiptsErrors 는 그 번째 목록 읽기만 실패시키고, onReceipts 는 계산한 값을 늦게 돌려준다")
  func receiptsErrorsAndLateHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      receiptsErrors: [1: .failed],
      onReceipts: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.save([ReceiptStoreFixture.receipt("a")])
        }
      }
    )
    fake.set(instance)

    // 훅을 기다리는 동안 저장한 이미지는 이미 계산한 결과에 들지 않는다.
    #expect(try await instance.receipts().isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await instance.receipts()
    }
    #expect(try await instance.receipts().map(\.id) == ["a"])
    #expect(indexes.withLock { $0 } == [0, 2])
    #expect(instance.receiptsCallCount == 3)
  }

  @Test("onSaveReceipts 는 쓰기 전에 기다려, 그동안 지워진 행에는 쓰지 않는다")
  func onSaveReceiptsRunsBeforeWriting() async throws {
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      images: [ReceiptStoreFixture.receipt("a", info: nil), ReceiptStoreFixture.receipt("b", info: nil)],
      onSaveReceipts: { _ in try? await fake.value?.delete(ids: ["a"]) }
    )
    fake.set(instance)

    try await instance.saveReceipts(["a": ReceiptStoreFixture.found, "b": ReceiptStoreFixture.found])

    #expect(instance.images.map(\.id) == ["b"])
    #expect(instance.images.first?.receipt == ReceiptStoreFixture.found)
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
