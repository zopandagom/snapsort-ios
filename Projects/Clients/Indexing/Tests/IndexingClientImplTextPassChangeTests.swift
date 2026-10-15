import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 분석 두 단계: 1단계(분류 저장)와 2단계(OCR 대기 이미지의 글자 읽기), 2단계 도중의 변경·멈춤·실패.
/// 2단계 도중의 보관함 변경·멈춤·저장 실패와 변경 스트림의 끝.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplTextPassChangeTests {
  @Test("2단계 도중 추가 변경이 오면 다음 배치 전에 새 이미지를 분류하고, 최신이라 다음 배치 맨 앞에서 읽는다")
  func classifiesInsertedImagesBetweenTextBatches() async {
    let added = ImageAsset.stub(id: "added", creationDate: date(month: 5, day: 9), isScreenshot: true)
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let fixture = Fixture(
      library: (1 ... 3).map { .stub(id: "day-\($0)", creationDate: date(month: 5, day: $0), isScreenshot: true) },
      loadable: [added],
      onRecognize: { id in
        if id == "day-3" {
          library.current?.sendIncrementalChange(inserted: [added])
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번. 그 뒤에 OCR 을 끝내 다음 배치 경계에서 반영되게 한다.
          await changeRequests.wait(until: 2)
        }
      },
      textBatchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished && $0.totalCount == 4 }

    #expect(fixture.photoLibrary.largestLoadIDs == ["day-3", "added", "day-2", "day-1"])
    let requests = fixture.photoLibrary.loadImageRequests
    let addedThumbnail = requests.firstIndex { $0 == LoadImageRequest(id: "added", size: .thumbnail) }
    let secondLargest = requests.firstIndex { $0 == LoadImageRequest(id: "added", size: .largestAvailable) }
    #expect(addedThumbnail.flatMap { thumbnail in secondLargest.map { thumbnail < $0 } } == true)
  }

  @Test("2단계 도중 삭제 변경이 오면 그 이미지의 결과를 지우고 OCR 하지 않는다")
  func deletesRemovedImagesBetweenTextBatches() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let fixture = Fixture(
      library: (1 ... 3).map { .stub(id: "day-\($0)", creationDate: date(month: 5, day: $0), isScreenshot: true) },
      onRecognize: { id in
        if id == "day-3" {
          library.current?.sendIncrementalChange(removed: ["day-2"])
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번. 그 뒤에 OCR 을 끝내 다음 배치 경계에서 반영되게 한다.
          await changeRequests.wait(until: 2)
        }
      },
      textBatchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished && $0.totalCount == 2 }

    #expect(fixture.photoLibrary.largestLoadIDs == ["day-3", "day-1"])
    #expect(fixture.store.deletedBatches == [["day-2"]])
    #expect(fixture.store.images.map(\.id) == ["day-1", "day-3"])
    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
  }

  @Test("2단계 도중 구독을 끝내면 저장하지 않은 배치를 버리고, 다음 실행은 다시 분류하지 않고 남은 대기부터 한다")
  func resumesTextPassAfterCancel() async {
    let consumer = ConsumerTask()
    let fixture = Fixture(
      library: (1 ... 3).map { .stub(id: "day-\($0)", creationDate: date(month: 5, day: $0), isScreenshot: true) },
      onRecognize: { id in
        // 첫 배치(day-3, day-2)의 두 번째 이미지를 읽을 때 구독을 끝낸다.
        if id == "day-2" {
          consumer.cancel()
        }
      },
      textBatchSize: 2
    )

    consumer.start {
      for await _ in fixture.indexing.run() {}
    }
    await consumer.wait()
    while fixture.photoLibrary.imageChangesSubscriberCount > 0 {
      await Task.yield()
    }
    #expect(fixture.store.savedBatches.count == 1)
    #expect(fixture.store.images.allSatisfy { $0.textRecognition == .pending })

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0, recognizedTextCount: 3))
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.size == .thumbnail } == 3)
  }

  @Test("2단계에서 저장하지 못하면 변경 스트림이 끝나지 않아도 멈추고 스트림을 끝낸다")
  func finishesWhenTextSaveFails() async {
    let fixture = Fixture(library: .stubs(count: 3), saveLimit: 1)

    var received: [IndexingProgress] = []
    for await progress in fixture.indexing.run() {
      received.append(progress)
    }

    #expect(fixture.store.savedBatches.map(\.count) == [3])
    #expect(received.last == IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0, pendingTextCount: 3))
    #expect(fixture.store.images.allSatisfy { $0.textRecognition == .pending })
  }

  @Test("변경 스트림이 끝나면 남은 변경을 반영하고 2단계를 끝까지 한 뒤 스트림을 끝낸다")
  func finishesAfterRemainingWorkWhenChangesEnd() async {
    let added = ImageAsset.stub(id: "added", isScreenshot: true)
    let gate = Gate()
    let fixture = Fixture(
      library: [.stub(id: "a", isScreenshot: true)],
      loadable: [added],
      onRecognize: { _ in await gate.wait() }
    )

    var received: [IndexingProgress] = []
    let stream = fixture.indexing.run()
    while fixture.photoLibrary.imageChangesSubscriberCount == 0 {
      await Task.yield()
    }
    fixture.photoLibrary.sendIncrementalChange(inserted: [added])
    fixture.photoLibrary.finishImageChanges()
    gate.open()
    for await progress in stream {
      received.append(progress)
    }

    #expect(received.last == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
    #expect(fixture.store.images.allSatisfy { $0.textLines != nil })
  }

  @Test("2단계 도중 제한 접근으로 바뀌면 고르지 않은 대기 이미지의 결과를 지우고 읽지 않는다")
  func deletesUnselectedPendingWhenLimited() async {
    let selected = ImageAsset.stub(id: "selected", isScreenshot: true)
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let fixture = Fixture(
      library: [selected, .stub(id: "unselected", isScreenshot: true)],
      onRecognize: { id in
        if id == "selected" {
          library.current?.sendReloadAll(imageAssets: [selected], accessState: .limited)
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번. 그 뒤에 OCR 을 끝내 다음 배치 경계에서 반영되게 한다.
          await changeRequests.wait(until: 2)
        }
      },
      textBatchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished && $0.totalCount == 1 }

    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
    #expect(fixture.photoLibrary.largestLoadIDs == ["selected"])
    #expect(fixture.store.images.map(\.id) == ["selected"])
  }
}
