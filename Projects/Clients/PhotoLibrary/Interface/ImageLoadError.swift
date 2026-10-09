/// 이미지를 읽지 못한 이유. 받는 쪽은 이유마다 다르게 처리한다.
public enum ImageLoadError: Error, Equatable {
  /// 보관함에 없는 식별자 (삭제, 제한 접근 선택에서 빠짐). 받는 쪽은 이 이미지의 결과를 지운다.
  case notFound
  /// 기기에 읽을 수 있는 버전이 없고 iCloud 에만 있다. 내려받지 않으므로 받는 쪽은 나중에 다시 시도한다.
  case notAvailableLocally
  /// 호출한 Task 가 취소되어 읽기를 멈췄다. 받는 쪽은 결과를 남기지 않는다.
  case cancelled
  /// 그 밖의 실패 (손상된 파일, 디코딩 실패 등).
  case failed
}
