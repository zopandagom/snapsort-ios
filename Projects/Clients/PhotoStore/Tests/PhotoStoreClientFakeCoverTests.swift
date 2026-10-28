import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing

/// Fake 의 대표 조회. 같은 표는 `PhotoStoreClientImplCoverTests` 가 Impl 로 본다.
struct PhotoStoreClientFakeCoverTests {
  @Test("Fake 도 Impl 과 같은 표로 대표를 준다")
  func sameTableAsImpl() async throws {
    let fake = PhotoStoreClientFake(
      images: CoverFixture.mixedImages + [.stub(id: "t1"), .stub(id: "t3")],
      trips: [
        CoverFixture.trip(["t1", "t2", "t3"], start: 100),
        // 후보가 모두 저장소에 없어 건너뛴다.
        CoverFixture.trip(["gone"], start: 300),
        CoverFixture.trip([], start: 400),
        CoverFixture.trip(["t3"], start: 200, end: 5000),
      ]
    )

    let covers = try await fake.categoryCovers(limit: 3)

    #expect(covers == [
      .chat: ["x", "10", "9"],
      .shopping: ["a", "s1", "U2"],
      .document: ["d1", "d2", "10"],
      .food: ["x"],
      .travel: ["t3"],
    ])
    #expect(try await fake.categoryCovers(limit: 4)[.travel] == ["t3", "t1"])
    #expect(try await fake.categoryCovers(limit: 0).isEmpty)
    for category in ImageCategory.allCases where category != .travel {
      let expected = try await fake.assets(in: category).prefix(3).map(\.id)
      #expect((covers[category] ?? []) == expected, "\(category)")
    }
  }

  @Test("호출 번호별 실패는 그 호출만 던지고 호출 수에는 실패한 호출도 센다")
  func errorsByCallIndex() async throws {
    let fake = PhotoStoreClientFake(
      images: [.stub(id: "a", categories: [.food])],
      categoryCoversErrors: [1: .failed]
    )

    #expect(try await fake.categoryCovers(limit: 4) == [.food: ["a"]])
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.categoryCovers(limit: 4)
    }
    #expect(try await fake.categoryCovers(limit: 4) == [.food: ["a"]])
    #expect(fake.categoryCoversCallCount == 3)
  }

  @Test("늦은 결과 훅을 기다리는 동안 바뀐 저장소가 아니라 앞서 계산한 값을 준다")
  func hookWaitsAfterComputing() async throws {
    let indexes = Mutex<[Int]>([])
    let later = Later<PhotoStoreClientFake>()
    let fake = PhotoStoreClientFake(
      onCategoryCovers: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await later.value?.save([.stub(id: "a", categories: [.food])])
        }
      }
    )
    later.set(fake)

    #expect(try await fake.categoryCovers(limit: 4).isEmpty)
    #expect(try await fake.categoryCovers(limit: 4) == [.food: ["a"]])
    #expect(indexes.withLock { $0 } == [0, 1])
  }

  @Test("error 가 정해져 있으면 던지고 호출 수를 세지 않는다")
  func globalErrorIsNotCounted() async {
    let fake = PhotoStoreClientFake(error: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.categoryCovers(limit: 4)
    }
    #expect(fake.categoryCoversCallCount == 0)
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
