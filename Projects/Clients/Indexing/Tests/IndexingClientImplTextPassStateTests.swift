import Core
import Foundation
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 2단계에서 보관함에 없다고 나오거나 저장 결과가 없을 때, 인덱서 상태가 저장소와 어긋나지 않는지.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplTextPassStateTests {
  @Test("2단계에서 보관함에 없다고 나온 이미지가 삭제 없이 다시 추가되면 대기로 되돌려 다시 읽는다")
  func returnsGoneImageToPendingWhenInsertedAgain() async throws {
    let back = ImageAsset.stub(id: "back", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let gate = Gate()
    let fixture = Fixture(
      library: [back, .stub(id: "ok", creationDate: date(month: 5, day: 1), isScreenshot: true)],
      largestErrors: ["back": .notFound],
      // 처음에는 원본을 읽지 못해 OCR 하지 않으므로, 되돌아온 뒤의 OCR 만 붙잡는다.
      onRecognize: { id in
        if id == "back" {
          await gate.wait()
        }
      }
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let gone = await progress.next { $0.isFinished }
    #expect(gone == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
    fixture.loadFailures.remove("back")
    fixture.photoLibrary.sendIncrementalChange(inserted: [back])
    // OCR 을 붙잡아 두었으므로 이 값은 변경을 반영한 직후의 진행률이다.
    let returned = try #require(await progress.next { $0.totalCount == 2 })
    gate.open()
    let finished = await progress.next { $0.isFinished }

    #expect(returned == IndexingProgress(
      totalCount: 2,
      indexedCount: 2,
      skippedCount: 0,
      pendingTextCount: 1,
      recognizedTextCount: 1
    ))
    #expect(returned.phase == .recognizingText)
    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
    #expect(fixture.store.images.first { $0.id == "back" }?.textRecognition == .recognized([]))
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.id == "back" && $0.size == .thumbnail } == 1)
  }

  @Test("2단계에서 보관함에 없다고 나온 뒤 삭제 변경이 오면 행을 지우고, 다시 추가되면 1단계부터 분류한다")
  func reclassifiesGoneImageAfterRemoval() async {
    let back = ImageAsset.stub(id: "back", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let fixture = Fixture(
      library: [back, .stub(id: "ok", creationDate: date(month: 5, day: 1), isScreenshot: true)],
      largestErrors: ["back": .notFound]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.loadFailures.remove("back")
    fixture.photoLibrary.sendIncrementalChange(removed: ["back"])
    fixture.photoLibrary.sendIncrementalChange(inserted: [back])
    let finished = await progress.next { $0.isFinished && $0.totalCount == 2 && $0.recognizedTextCount == 2 }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
    #expect(fixture.store.deletedBatches == [["back"]])
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.id == "back" && $0.size == .thumbnail } == 2)
    #expect(fixture.store.images.first { $0.id == "back" }?.textRecognition == .recognized([]))
  }

  @Test("같은 변경에 삭제와 추가가 함께 오면 행을 지우고 1단계부터 분류한다")
  func reclassifiesGoneImageRemovedAndInsertedTogether() async {
    let back = ImageAsset.stub(id: "back", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let fixture = Fixture(
      library: [back, .stub(id: "ok", creationDate: date(month: 5, day: 1), isScreenshot: true)],
      largestErrors: ["back": .notFound]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.loadFailures.remove("back")
    fixture.photoLibrary.sendIncrementalChange(inserted: [back], removed: ["back"])
    let finished = await progress.next { $0.isFinished && $0.totalCount == 2 && $0.recognizedTextCount == 2 }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
    #expect(fixture.store.deletedBatches == [["back"]])
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.id == "back" && $0.size == .thumbnail } == 2)
  }

  @Test("2단계에서 저장 결과가 없는 대기 이미지는 1단계 미룸으로 세어 진행을 마치고, 전체 다시 비교에서 다시 시도한다")
  func countsMissingStoredImageAsSkipped() async {
    let receipt = ImageAsset.stub(id: "receipt", isScreenshot: true)
    let fixture = Fixture(
      library: [receipt],
      stored: [pending(receipt)],
      missingOnIDRead: ["receipt"]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let skipped = await progress.next { $0.isFinished }
    #expect(skipped == IndexingProgress(totalCount: 1, indexedCount: 0, skippedCount: 1))
    #expect(fixture.photoLibrary.loadImageRequests.isEmpty)

    fixture.store.restoreIDReads()
    fixture.photoLibrary.sendReloadAll(imageAssets: [receipt])
    let retried = await progress.next { $0.isFinished && $0.recognizedTextCount == 1 }

    #expect(retried == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
  }

  @Test("1단계에서 보관함에 없다고 나온 이미지가 다시 추가되면 1단계 대상이다")
  func reclassifiesImageGoneInClassification() async {
    let back = ImageAsset.stub(id: "back", isScreenshot: true)
    let fixture = Fixture(library: [back, .stub(id: "ok", isScreenshot: true)])
    fixture.loadFailures.setAllSizes("back", .notFound)

    var progress = fixture.indexing.run().makeAsyncIterator()
    let gone = await progress.next { $0.isFinished }
    #expect(gone == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
    fixture.loadFailures.remove("back")
    fixture.photoLibrary.sendIncrementalChange(inserted: [back])
    let finished = await progress.next { $0.isFinished && $0.totalCount == 2 }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.id == "back" && $0.size == .thumbnail } == 2)
  }
}
