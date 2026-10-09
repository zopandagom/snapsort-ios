/// 분석에 쓸 이미지 크기. 픽셀 기준은 구현이 정한다.
public enum ImageSize: Sendable, Equatable {
  /// 이미지 분류용 작은 이미지.
  case thumbnail
  /// 기기에 있는 가장 큰 버전. OCR·바코드용. 메모리를 아끼려고 픽셀 수에 상한을 둔다.
  /// 원본이 iCloud 에만 있으면 기기에서 바로 줄 수 있는 버전이고, 그중 가장 크다는 보장은 없다.
  case largestAvailable
}
