import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 만의 기프티콘 목록·사용 여부 훅과 실패. 같은 동작은 `PhotoStoreGifticonListTests` 가 Impl 과 함께 본다.
struct PhotoStoreClientFakeGifticonListTests {
  @Test("처음 사용함은 들어간 기프티콘 이미지만 남긴다")
  func keepsOnlyGifticonUsedIDs() {
    let fake = PhotoStoreClientFake(
      images: [Self.gifticon("a"), .stub(id: "r", categories: [.receipt])],
      usedIDs: ["a", "r", "missing"]
    )

    #expect(fake.usedIDs == ["a"])
  }

  @Test("목록 읽기는 정한 번째 호출만 실패하고, 훅은 성공한 호출에서 계산한 뒤 번호를 받는다")
  func failsGifticonsByCallAndCallsHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      gifticonsErrors: [1: .failed],
      onGifticons: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.save([Self.gifticon("a")])
        }
      }
    )
    fake.set(instance)

    // 훅을 기다리는 동안 저장한 이미지는 이미 계산한 결과에 들지 않는다.
    #expect(try await instance.gifticons().isEmpty)
    await #expect(throws: PhotoStoreError.failed) {
      try await instance.gifticons()
    }
    #expect(try await instance.gifticons().map(\.id) == ["a"])
    #expect(instance.gifticonsCallCount == 3)
    #expect(indexes.withLock { $0 } == [0, 2])
  }

  @Test("한 장 읽기 훅은 계산한 뒤 번호를 받는다")
  func callsGifticonHookAfterComputing() async throws {
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      images: [Self.gifticon("a")],
      onGifticon: { index in
        if index == 0 {
          _ = try? await fake.value?.setGifticonUsed(true, id: "a")
        }
      }
    )
    fake.set(instance)

    #expect(try await instance.gifticon(id: "a")?.isUsed == false)
    #expect(try await instance.gifticon(id: "a")?.isUsed == true)
  }

  @Test("사용 여부 쓰기는 훅을 기다린 뒤 쓰고, 실패를 정하면 바꾸지 않고 던지며 모든 호출을 센다")
  func waitsHookAndFailsSettingUsage() async throws {
    let seenDuringHook = Mutex<[Set<ImageAsset.ID>]>([])
    let fake = Later<PhotoStoreClientFake>()
    let instance = PhotoStoreClientFake(
      images: [Self.gifticon("a")],
      onSetGifticonUsed: { _ in
        let used = fake.value?.usedIDs ?? []
        seenDuringHook.withLock { $0.append(used) }
      }
    )
    fake.set(instance)
    let failing = PhotoStoreClientFake(images: [Self.gifticon("a")], setUsedError: .failed)

    #expect(try await instance.setGifticonUsed(true, id: "a"))
    await #expect(throws: PhotoStoreError.failed) {
      try await failing.setGifticonUsed(true, id: "a")
    }

    #expect(seenDuringHook.withLock { $0 } == [[]])
    #expect(instance.usedIDs == ["a"])
    #expect(instance.setGifticonUsedCount == 1)
    #expect(failing.usedIDs.isEmpty)
    #expect(failing.setGifticonUsedCount == 1)
    // 다른 호출은 성공한다.
    #expect(try await failing.gifticons().map(\.id) == ["a"])
  }

  @Test("모든 호출 실패를 정하면 목록·한 장 읽기·사용 여부 쓰기도 던진다")
  func throwsConfiguredErrorForGifticonCalls() async {
    let fake = PhotoStoreClientFake(images: [Self.gifticon("a")], error: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.gifticons()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.gifticon(id: "a")
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.setGifticonUsed(true, id: "a")
    }
    #expect(fake.usedIDs.isEmpty)
  }

  private static func gifticon(_ id: String) -> IndexedImage {
    .stub(
      id: id,
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    )
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
