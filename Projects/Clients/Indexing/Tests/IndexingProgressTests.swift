import IndexingInterface
import Testing

struct IndexingProgressTests {
  @Test(
    "모든 이미지를 분석했거나 미뤘을 때만 끝난 것으로 본다",
    arguments: [
      (IndexingProgress(totalCount: 0, indexedCount: 0, skippedCount: 0), true),
      (IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 1), false),
      (IndexingProgress(totalCount: 3, indexedCount: 2, skippedCount: 1), true),
      (IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0), true),
    ]
  )
  func isFinished(progress: IndexingProgress, expected: Bool) {
    #expect(progress.isFinished == expected)
  }
}
