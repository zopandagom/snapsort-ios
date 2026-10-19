import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import IndexingImpl

/// 소급 추출의 저장소 실패: 이번 실행에서는 소급만 멈추고 인덱싱은 이어 가며, 취소는 삼키지 않는다.
/// 고치기 전처럼 실패로 스트림이 끝나면 진행률·변경 기다림이 끝나지 않아 시간 제한으로 실패한다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplGifticonFailureTests {
  @Test("추출 값을 저장하지 못하면 이번 실행에서는 소급만 멈추고 인덱싱은 이어 가며, 다음 실행이 남은 이미지를 소급 추출한다")
  func continuesIndexingWhenBackfillSaveFails() async {
    let library = Later<PhotoLibraryClientFake>()
    let attempts = CallCount()
    let targets = ["a", "b", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 4 - index), isScreenshot: true)
    }
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let newPhoto = ImageAsset.stub(id: "n", creationDate: date(month: 6, day: 1), coordinate: seoul)
    let fixture = Fixture(
      library: targets + [ocrPending],
      loadable: [newPhoto],
      stored: targets.map { recognizedGifticon($0, text: gifticonText) } + [pending(ocrPending)],
      labels: ["n": photoLabels],
      text: ["p": receiptText],
      gifticonSaveLimit: 1,
      onSaveGifticons: { _ in attempts.record() },
      batchSize: 1
    )
    library.set(fixture.photoLibrary)

    var progress = fixture.indexing.run().makeAsyncIterator()
    // 소급은 2단계보다 먼저 돈다. 저장 실패 뒤에도 스트림이 끝나지 않고 2단계와 새 사진 분류를 한다.
    let recognized = await progress.next { $0.isFinished && $0.recognizedTextCount == 1 }
    library.current?.sendIncrementalChange(inserted: [newPhoto])
    let afterChange = await progress.next { $0.isFinished && $0.totalCount == 5 }
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(recognized != nil)
    #expect(afterChange != nil)
    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [["a"]])
    // a 성공, b 실패. 같은 실행에서 c 나 b 를 다시 시도하지 않는다.
    #expect(attempts.calls == 2)
    let images = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(images["p"]?.textLines != nil)
    #expect(images["n"] != nil)
    #expect(fixture.storedGifticons == ["a": extractedGifticon])

    let next = Fixture(library: targets + [ocrPending, newPhoto], stored: fixture.store.images, batchSize: 1)
    await next.runToEnd()

    #expect(next.store.savedGifticonBatches.reduce(into: Set()) { $0.formUnion($1.keys) } == ["b", "c"])
    #expect(next.storedGifticons == ["a": extractedGifticon, "b": extractedGifticon, "c": extractedGifticon])
  }

  @Test("소급 배치의 저장 줄을 읽지 못하면 이번 실행에서는 소급만 멈추고 글자 읽기·새 사진 분류는 이어 가며, 다음 실행이 소급 추출한다")
  func continuesIndexingWhenBackfillReadFails() async {
    let library = Later<PhotoLibraryClientFake>()
    let attempts = CallCount()
    let targets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let newPhoto = ImageAsset.stub(id: "n", creationDate: date(month: 6, day: 1), coordinate: seoul)
    let fixture = Fixture(
      library: targets + [ocrPending],
      loadable: [newPhoto],
      stored: targets.map { recognizedGifticon($0, text: gifticonText) } + [pending(ocrPending)],
      labels: ["n": photoLabels],
      text: ["p": receiptText],
      onSaveGifticons: { _ in attempts.record() },
      failingOnIDRead: ["a"],
      batchSize: 1
    )
    library.set(fixture.photoLibrary)

    var progress = fixture.indexing.run().makeAsyncIterator()
    // 2단계 배치는 OCR 대기 행(p)을 읽으므로 소급 대상(a)의 읽기 실패와 겹치지 않는다.
    let recognized = await progress.next { $0.isFinished && $0.recognizedTextCount == 1 }
    library.current?.sendIncrementalChange(inserted: [newPhoto])
    let afterChange = await progress.next { $0.isFinished && $0.totalCount == 4 }
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(recognized != nil)
    #expect(afterChange != nil)
    // a 배치 읽기에서 실패해 대상을 비웠으므로 같은 실행에서 b 도 시도하지 않는다.
    #expect(fixture.store.savedGifticonBatches.isEmpty)
    #expect(attempts.calls == 0)
    let images = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(images["p"]?.textLines != nil)
    #expect(images["n"] != nil)
    #expect(fixture.storedGifticons.isEmpty)

    let next = Fixture(library: targets + [ocrPending, newPhoto], stored: fixture.store.images, batchSize: 1)
    await next.runToEnd()

    #expect(next.storedGifticons == ["a": extractedGifticon, "b": extractedGifticon])
  }

  @Test("소급 추출에 실패한 뒤 전체 다시 비교가 오면 같은 실행에서 남은 대상을 다시 시도한다")
  func retriesBackfillOnReloadAll() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let attempts = CallCount()
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      gifticonSaveLimit: 0,
      onSaveGifticons: { _ in
        switch attempts.record() {
        case 1:
          library.current?.sendReloadAll(imageAssets: assets)
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번.
          await changeRequests.wait(until: 2)
        default:
          library.current?.finishImageChanges()
        }
      },
      batchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    for await _ in fixture.indexing.run() {}

    // 첫 실패 1번 + 다시 비교 뒤 1번. 실패하면 대상을 비우므로 같은 비교 안에서 b 로 넘어가지 않는다.
    #expect(attempts.calls == 2)
    #expect(fixture.store.savedGifticonBatches.isEmpty)
  }

  @Test("소급 대상을 조회하지 못해도 분류·글자 읽기는 이어 가고 소급만 하지 않는다")
  func continuesIndexingWhenBackfillTargetsFail() async {
    let target = ImageAsset.stub(id: "a", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let newPhoto = ImageAsset.stub(id: "n", creationDate: date(month: 4, day: 1), coordinate: seoul)
    let fixture = Fixture(
      library: [ocrPending, target, newPhoto],
      stored: [recognizedGifticon(target, text: gifticonText), pending(ocrPending)],
      labels: ["n": photoLabels],
      text: ["p": gifticonText],
      gifticonError: .failed
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished && $0.totalCount == 3 && $0.recognizedTextCount == 1 }
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(finished != nil)
    #expect(fixture.store.savedGifticonBatches.isEmpty)
    let images = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(images["n"] != nil)
    // 2단계 저장은 소급 실패와 관계없이 추출 값까지 저장한다.
    #expect(fixture.storedGifticons == ["p": extractedGifticon])
  }

  @Test("소급 추출 도중 구독을 끝내면 저장 실패와 겹쳐도 멈춘다")
  func stopsOnCancelDuringFailedBackfill() async {
    let consumer = ConsumerTask()
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: assets + [ocrPending],
      stored: assets.map { recognizedGifticon($0, text: gifticonText) } + [pending(ocrPending)],
      text: ["p": receiptText],
      gifticonSaveLimit: 0,
      onSaveGifticons: { _ in consumer.cancel() },
      batchSize: 1
    )

    consumer.start {
      for await _ in fixture.indexing.run() {}
    }
    await consumer.wait()
    // 인덱싱 Task 가 끝나면 변경 구독도 끝난다. 그 뒤에 2단계에 들어가지 않았는지 본다.
    while fixture.photoLibrary.imageChangesSubscriberCount > 0 {
      await Task.yield()
    }

    #expect(!fixture.analysis.requests.contains(.recognizeText))
    #expect(fixture.photoLibrary.largestLoadIDs.isEmpty)
  }

  @Test("취소된 Task 에서 소급 배치를 부르면 대상을 그대로 두고 진행률을 보내지 않은 채 취소로 멈춘다")
  func backfillBatchRethrowsCancellation() async {
    let attempts = CallCount()
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      onSaveGifticons: { _ in attempts.record() }
    )

    let (stop, remaining, reportCount) = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      var run = IndexingRun(
        photoLibrary: fixture.photoLibrary,
        imageAnalysis: fixture.analysis,
        photoStore: fixture.store,
        calendar: Fixture.seoulCalendar,
        batchSize: 1,
        textBatchSize: 1
      )
      run.assets = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
      run.pendingGifticonIDs = ["a", "b"]
      var reportCount = 0
      do throws(IndexingStop) {
        try await run.extractGifticonBatch { _ in reportCount += 1 }
        return (IndexingStop?.none, run.pendingGifticonIDs, reportCount)
      } catch {
        return (IndexingStop?.some(error), run.pendingGifticonIDs, reportCount)
      }
    }.value

    #expect(stop == .cancelled)
    #expect(remaining == ["a", "b"])
    #expect(reportCount == 0)
    #expect(attempts.calls == 0)
    #expect(fixture.store.savedGifticonBatches.isEmpty)
  }

  @Test("추출 값을 저장하지 못해 소급을 멈춰도 직전과 같은 값의 진행률을 한 번 더 보낸다")
  func reportsOnceWhenBackfillStops() async {
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      gifticonSaveLimit: 0,
      batchSize: 1
    )
    let extractedFixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText, gifticon: extractedGifticon) },
      batchSize: 1
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await extractedFixture.allProgress()

    #expect(fixture.storedGifticons.isEmpty)
    #expect(Array(progresses.dropLast()) == progressesWithoutTargets)
    #expect(progresses.last == progressesWithoutTargets.last)
  }
}

/// 저장소 Fake 의 훅이 불린 횟수. 다른 Task 에서 늘리므로 Mutex 로 보호한다.
final class CallCount: Sendable {
  private let value = Mutex(0)

  /// 한 번 세고 지금까지의 횟수를 돌려준다.
  @discardableResult
  func record() -> Int {
    self.value.withLock { value in
      value += 1
      return value
    }
  }

  var calls: Int {
    self.value.withLock { $0 }
  }
}
