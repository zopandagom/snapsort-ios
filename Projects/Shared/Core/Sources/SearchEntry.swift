/// 검색 대상 이미지 한 장: 글자를 읽은 이미지의 메타데이터·OCR 줄 원문·캡처 묶음 값 (docs/ARCHITECTURE.md §4 검색).
/// OCR 텍스트를 담으므로 로그에 남기지 않는다.
public struct SearchEntry: Sendable, Hashable, Identifiable {
  public let asset: ImageAsset
  /// OCR 줄 원문, 읽은 순서. 줄을 디코딩하지 못한 행은 빈 배열.
  public let lines: [String]
  /// 지금 규칙 버전으로 추출한 묶음 값. 추출 대기(다른 버전·풀 수 없는 식별자)면 nil(줄로만 찾는다).
  public let captureGroups: CaptureGroups?

  public var id: ImageAsset.ID {
    self.asset.id
  }

  public init(asset: ImageAsset, lines: [String], captureGroups: CaptureGroups?) {
    self.asset = asset
    self.lines = lines
    self.captureGroups = captureGroups
  }
}
