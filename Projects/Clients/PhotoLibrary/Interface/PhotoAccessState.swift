/// 사진 보관함 접근 권한 상태. PHAuthorizationStatus 를 Feature 에 노출하지 않기 위한 값 타입.
public enum PhotoAccessState: Sendable, Equatable {
  case authorized
  case limited
  case denied
  case notDetermined

  /// 이미지를 읽을 수 있는 상태인지. 제한 접근도 사용자가 고른 사진은 읽을 수 있다.
  public var canRead: Bool {
    self == .authorized || self == .limited
  }
}
