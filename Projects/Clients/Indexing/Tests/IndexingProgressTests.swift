import IndexingInterface
import Testing

struct IndexingProgressTests {
  @Test(
    "분류할 이미지가 남으면 1단계, OCR 대기가 남으면 2단계, 둘 다 없으면 끝난 것으로 본다",
    arguments: [
      (IndexingProgress(totalCount: 0, indexedCount: 0, skippedCount: 0), IndexingProgress.Phase.finished),
      (IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 1), .classifying),
      // 대기가 있어도 분류할 이미지가 남으면 1단계다.
      (IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 1, pendingTextCount: 1), .classifying),
      (IndexingProgress(totalCount: 3, indexedCount: 2, skippedCount: 1), .finished),
      (IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0, pendingTextCount: 2), .recognizingText),
      (
        IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0, pendingTextCount: 1, recognizedTextCount: 1),
        .recognizingText
      ),
      // 2단계 미룸만 남으면 끝난 것이다.
      (
        IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0, recognizedTextCount: 1, skippedTextCount: 2),
        .finished
      ),
    ]
  )
  func phase(progress: IndexingProgress, expected: IndexingProgress.Phase) {
    #expect(progress.phase == expected)
    #expect(progress.isFinished == (expected == .finished))
  }
}
