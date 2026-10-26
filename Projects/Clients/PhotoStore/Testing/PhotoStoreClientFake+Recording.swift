import Core
import PhotoStoreInterface

// 호출 기록. 저장 속성은 PhotoStoreClientFake.swift 본문에 둔다.
public extension PhotoStoreClientFake {
  /// `save` 에 넘긴 이미지 목록을 부른 순서대로.
  var savedBatches: [[IndexedImage]] {
    self.state.withLock { $0.savedBatches }
  }

  /// `saveGifticons` 에 넘긴 추출 값을 부른 순서대로. 실패한 호출은 빠진다.
  var savedGifticonBatches: [[ImageAsset.ID: GifticonInfo]] {
    self.state.withLock { $0.savedGifticonBatches }
  }

  /// `saveGifticonModelFills` 에 넘긴 보강 결과를 부른 순서대로. 실패한 호출은 빠진다.
  var savedModelFillBatches: [[ImageAsset.ID: GifticonModelFillResult]] {
    self.state.withLock { $0.savedModelFillBatches }
  }

  /// 지금까지 `assets(in:)` 을 부른 횟수. `assetsErrors` 로 실패한 호출은 포함하고, `error`(모든 호출 실패)로 던진 호출은 세지 않는다
  /// (`throwIfNeeded` 가 번호를 매기기 전에 던진다). 재조회 합치기 테스트가 센다.
  var assetsCallCount: Int {
    self.state.withLock { $0.assetsCallCount }
  }

  /// `delete` 에 넘긴 식별자를 부른 순서대로.
  var deletedBatches: [Set<ImageAsset.ID>] {
    self.state.withLock { $0.deletedBatches }
  }
}
