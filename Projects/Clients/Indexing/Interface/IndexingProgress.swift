/// 인덱싱 진행률. 진행 막대와 "분석 중" 표시에 쓴다.
public struct IndexingProgress: Sendable, Equatable {
  /// 보관함 이미지 수.
  public let totalCount: Int
  /// 분석을 마치고 저장한 이미지 수.
  public let indexedCount: Int
  /// 이번 실행에서 읽거나 분석하지 못해 미룬 이미지 수 (iCloud 에만 있음, 손상된 파일 등).
  /// 저장하지 않으므로 다음 실행에서 다시 시도한다.
  public let skippedCount: Int

  public init(totalCount: Int, indexedCount: Int, skippedCount: Int) {
    self.totalCount = totalCount
    self.indexedCount = indexedCount
    self.skippedCount = skippedCount
  }

  /// 보관함의 모든 이미지를 분석했거나 미뤘는지.
  public var isFinished: Bool {
    self.indexedCount + self.skippedCount >= self.totalCount
  }
}
