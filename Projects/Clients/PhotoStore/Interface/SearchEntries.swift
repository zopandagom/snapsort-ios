import Core

/// `PhotoStoreClient.searchEntries()` 의 결과 (docs/ARCHITECTURE.md §4 검색). OCR 줄을 담으므로 로그에 남기지 않는다.
public struct SearchEntries: Sendable, Equatable {
  public let entries: [SearchEntry]
  /// OCR 대기 이미지 수. iCloud 에만 있어 2단계가 미룬 이미지도 대기로 남아 여기에 든다.
  public let pendingTextCount: Int

  public init(entries: [SearchEntry], pendingTextCount: Int) {
    self.entries = entries
    self.pendingTextCount = pendingTextCount
  }
}
