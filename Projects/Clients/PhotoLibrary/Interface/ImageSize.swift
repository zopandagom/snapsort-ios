/// 분석에 쓸 이미지 크기. 픽셀 기준은 구현이 정한다.
public enum ImageSize: Sendable, Equatable {
  /// 이미지 분류용 작은 이미지.
  case thumbnail
  /// 기기에 있는 가장 큰 버전. OCR·바코드용. 원본이 iCloud 에만 있으면 기기에 남은 작은 버전이다.
  case largestAvailable
}
