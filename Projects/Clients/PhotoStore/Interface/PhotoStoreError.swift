/// 저장소를 읽거나 쓰지 못한 이유.
public enum PhotoStoreError: Error, Equatable {
  /// 저장소를 열거나 읽고 쓰지 못했다 (디스크 공간 부족, 손상된 저장 파일 등).
  case failed
}
