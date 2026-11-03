import Core

/// 보관함 홈 "곧 만료" 띠. LibraryModel 파일 길이 때문에 나눴다. 읽기·다시 계산은 `LibraryExpiringStrip`.
public extension LibraryModel {
  /// 곧 만료 띠. nil 이거나 비면(`isEmpty`) 숨긴다. 도우미 `LibraryExpiringStrip.current` 참고.
  var expiringGifticons: ExpiringGifticons? {
    self.expiringStrip.current
  }

  /// 띠 칩 썸네일로 보관할 식별자(최대 `expiringLimit` 개, 칩 순서). LibraryView 가 바뀔 때마다
  /// `LibraryCoverModel.expiringChanged(_:)` 로 넘긴다.
  var expiringThumbnailIDs: [ImageAsset.ID] {
    self.expiringGifticons?.items.map(\.id) ?? []
  }
}

extension LibraryModel {
  /// 곧 만료 띠의 칩 수 상한(썸네일 상한). 보관함 화면 썸네일 전체 상한은 카드 대표 48(`coverLimit` × 카테고리 수)에
  /// 이 값을 더한 68장이다(docs/ARCHITECTURE.md §4 카테고리 화면).
  static let expiringLimit = 20
}
