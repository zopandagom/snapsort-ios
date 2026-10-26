import Core
import PhotoStoreInterface

// 호출 기록. 저장 속성은 PhotoStoreClientFake.swift 본문에 둔다.
public extension PhotoStoreClientFake {
  /// `delete` 에 넘긴 식별자를 부른 순서대로.
  var deletedBatches: [Set<ImageAsset.ID>] {
    self.state.withLock { $0.deletedBatches }
  }
}
