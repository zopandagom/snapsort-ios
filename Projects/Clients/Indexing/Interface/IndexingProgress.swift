/// 인덱싱 진행률. 진행 막대와 "분석 중" 표시에 쓴다.
/// 인덱서는 두 단계로 돈다: 1단계는 새 이미지를 모두 분류해 저장하고, 2단계는 OCR 대상의 글자를 나중에 읽는다.
public struct IndexingProgress: Sendable, Equatable {
  /// 인덱서가 지금 하는 단계. 수에서 계산하므로 수와 어긋나지 않는다.
  public enum Phase: Sendable, Equatable {
    /// 1단계: 분류해 저장할 이미지가 남았다.
    case classifying
    /// 2단계: 분류는 끝났고 OCR 을 기다리는 이미지가 남았다.
    case recognizingText
    /// 두 단계를 모두 마쳤거나 미뤘다.
    case finished
  }

  /// 보관함 이미지 수.
  public let totalCount: Int
  /// 1단계를 마치고(분류해) 저장한 이미지 수. OCR 대기 이미지도 들어간다.
  public let indexedCount: Int
  /// 이번 실행 1단계에서 읽거나 분석하지 못해 미룬 이미지 수 (iCloud 에만 있음, 손상된 파일, 분류할 수 없음 등).
  /// 저장하지 않으므로 다음 실행에서 다시 시도한다.
  public let skippedCount: Int
  /// 저장됐고 OCR 을 기다리는 이미지 수. 이번 실행 2단계에서 미룬 이미지는 빠진다.
  public let pendingTextCount: Int
  /// 이번 실행에서 글자를 읽어 저장한 이미지 수.
  public let recognizedTextCount: Int
  /// 이번 실행 2단계에서 원본을 읽거나 OCR 하지 못해 미룬 이미지 수. 1단계 결과(대기)로 남아 다음 실행에서 다시 시도한다.
  public let skippedTextCount: Int

  public init(
    totalCount: Int,
    indexedCount: Int,
    skippedCount: Int,
    pendingTextCount: Int = 0,
    recognizedTextCount: Int = 0,
    skippedTextCount: Int = 0
  ) {
    self.totalCount = totalCount
    self.indexedCount = indexedCount
    self.skippedCount = skippedCount
    self.pendingTextCount = pendingTextCount
    self.recognizedTextCount = recognizedTextCount
    self.skippedTextCount = skippedTextCount
  }

  /// 1단계에서 분류할 이미지가 남았으면 `.classifying`, OCR 대기가 남았으면 `.recognizingText`, 아니면 `.finished`.
  public var phase: Phase {
    if self.indexedCount + self.skippedCount < self.totalCount {
      return .classifying
    }
    return self.pendingTextCount > 0 ? .recognizingText : .finished
  }

  /// 두 단계를 모두 마쳤거나 미뤘는지.
  public var isFinished: Bool {
    self.phase == .finished
  }
}
