import Core

/// 보관함에서 이미지가 추가·삭제된 변경 한 건. 받는 쪽은 보관함 전체가 아니라 차이만 반영한다.
public enum ImageChange: Sendable, Equatable {
  /// 추가된 이미지는 메타데이터까지, 삭제된 이미지는 식별자만 준다.
  case incremental(inserted: [ImageAsset], removed: [ImageAsset.ID])
  /// 무엇이 바뀌었는지 알 수 없는 변경 (권한 변경, 한꺼번에 많이 바뀐 경우 등). 받는 쪽은 `fetchImageAssets()` 로 전체를 다시 조회한다.
  case reloadAll
}
