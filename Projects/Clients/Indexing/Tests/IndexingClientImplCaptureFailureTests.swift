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

/// 캡처 묶음 소급의 저장소 실패: 이번 실행에서는 캡처 묶음 소급만 멈추고 기프티콘·영수증 소급과 인덱싱은 이어 가며, 취소는 삼키지 않는다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplCaptureFailureTests {
  @Test("묶음 값을 저장하지 못하면 이번 실행에서는 캡처 묶음 소급만 멈추고 기프티콘·영수증 소급·글자 읽기·분류는 이어 가며, 다음 실행이 다시 소급한다")
  func continuesIndexingWhenCaptureGroupSaveFails() async {
    let library = Later<PhotoLibraryClientFake>()
    let attempts = CallCount()
    let targets = ["a", "b", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 4 - index), isScreenshot: true)
    }
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 4, day: 1), isScreenshot: true)
    let receipt = ImageAsset.stub(id: "r", creationDate: date(month: 4, day: 2), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let newPhoto = ImageAsset.stub(id: "n", creationDate: date(month: 6, day: 1), coordinate: seoul)
    let fixture = Fixture(
      library: targets + [coupon, receipt, ocrPending],
      loadable: [newPhoto],
      stored: targets.map { recognizedShopping($0) } + [
        recognizedGifticon(coupon, text: gifticonText),
        recognizedReceipt(receipt),
        pending(ocrPending),
      ],
      labels: ["n": photoLabels],
      text: ["p": shoppingText],
      captureGroup: CaptureGroupStoreOptions(saveLimit: 1, onSave: { _ in attempts.record() }),
      batchSize: 1
    )
    library.set(fixture.photoLibrary)

    var progress = fixture.indexing.run().makeAsyncIterator()
    let recognized = await progress.next { $0.isFinished && $0.recognizedTextCount == 1 }
    library.current?.sendIncrementalChange(inserted: [newPhoto])
    let afterChange = await progress.next { $0.isFinished && $0.totalCount == 7 }
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(recognized != nil)
    #expect(afterChange != nil)
    // a 성공, b 실패. 같은 실행에서 c 나 b 를 다시 시도하지 않는다.
    #expect(fixture.store.savedCaptureGroupBatches.map { Set($0.keys) } == [["a"]])
    #expect(attempts.calls == 2)
    #expect(fixture.storedGifticons == ["coupon": extractedGifticon])
    #expect(fixture.storedReceipts == ["r": extractedReceipt])
    // 2단계 저장은 캡처 묶음 소급 실패와 관계없이 묶음 값까지 저장한다.
    #expect(fixture.storedCaptureGroups == ["a": extractedShopping, "p": extractedShopping])
    #expect(fixture.store.images.contains { $0.id == "n" })

    let next = Fixture(
      library: targets + [coupon, receipt, ocrPending, newPhoto],
      stored: fixture.store.images,
      batchSize: 1
    )
    await next.runToEnd()

    #expect(next.store.savedCaptureGroupBatches.reduce(into: Set()) { $0.formUnion($1.keys) } == ["b", "c"])
    #expect(next.storedCaptureGroups == [
      "a": extractedShopping, "b": extractedShopping, "c": extractedShopping, "p": extractedShopping,
    ])
  }

  @Test("캡처 묶음 소급 대상을 조회하지 못해도 분류·글자 읽기는 이어 간다")
  func continuesIndexingWhenCaptureGroupTargetsFail() async {
    let target = ImageAsset.stub(id: "a", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let newPhoto = ImageAsset.stub(id: "n", creationDate: date(month: 4, day: 1), coordinate: seoul)
    let fixture = Fixture(
      library: [ocrPending, target, newPhoto],
      stored: [recognizedShopping(target), pending(ocrPending)],
      labels: ["n": photoLabels],
      text: ["p": shoppingText],
      captureGroup: CaptureGroupStoreOptions(error: .failed)
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished && $0.totalCount == 3 && $0.recognizedTextCount == 1 }
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(finished != nil)
    #expect(fixture.store.savedCaptureGroupBatches.isEmpty)
    #expect(fixture.store.images.contains { $0.id == "n" })
    // 2단계 저장(`save`)은 캡처 묶음 호출 실패와 따로 값을 저장한다.
    #expect(fixture.storedCaptureGroups == ["p": extractedShopping])
  }

  @Test("소급 배치의 저장 줄을 읽지 못하면 캡처 묶음 소급만 멈춘다")
  func stopsCaptureGroupBackfillWhenReadFails() async {
    let attempts = CallCount()
    let targets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: targets + [ocrPending],
      stored: targets.map { recognizedShopping($0) } + [pending(ocrPending)],
      text: ["p": shoppingText],
      failingOnIDRead: ["a"],
      captureGroup: CaptureGroupStoreOptions(onSave: { _ in attempts.record() }),
      batchSize: 1
    )

    await fixture.runToEnd()

    // a 배치 읽기에서 실패해 대상을 비웠으므로 같은 실행에서 b 도 시도하지 않는다.
    #expect(attempts.calls == 0)
    #expect(fixture.store.savedCaptureGroupBatches.isEmpty)
    #expect(fixture.storedCaptureGroups == ["p": extractedShopping])

    let next = Fixture(library: targets + [ocrPending], stored: fixture.store.images, batchSize: 1)
    await next.runToEnd()

    #expect(next.storedCaptureGroups == ["a": extractedShopping, "b": extractedShopping, "p": extractedShopping])
  }

  @Test("캡처 묶음 소급을 실패로 멈춰도 직전과 같은 값의 진행률을 한 번 보낸다")
  func reportsOnceWhenCaptureGroupBackfillStops() async {
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedShopping($0) },
      captureGroup: CaptureGroupStoreOptions(saveLimit: 0),
      batchSize: 1
    )
    let extractedFixture = Fixture(
      library: assets,
      stored: assets.map { recognizedShopping($0, groups: extractedShopping) },
      batchSize: 1
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await extractedFixture.allProgress()

    #expect(fixture.storedCaptureGroups.isEmpty)
    #expect(Array(progresses.dropLast()) == progressesWithoutTargets)
    #expect(progresses.last == progressesWithoutTargets.last)
  }

  @Test("캡처 묶음 소급 실패 뒤 전체 다시 비교가 오면 같은 실행에서 다시 시도한다")
  func retriesCaptureGroupBackfillOnReloadAll() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let attempts = CallCount()
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedShopping($0) },
      captureGroup: CaptureGroupStoreOptions(saveLimit: 0, onSave: { _ in
        switch attempts.record() {
        case 1:
          library.current?.sendReloadAll(imageAssets: assets)
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번.
          await changeRequests.wait(until: 2)
        default:
          library.current?.finishImageChanges()
        }
      }),
      batchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    for await _ in fixture.indexing.run() {}

    // 첫 실패 1번 + 다시 비교 뒤 1번. 실패하면 대상을 비우므로 같은 비교 안에서 b 로 넘어가지 않는다.
    #expect(attempts.calls == 2)
    #expect(fixture.store.savedCaptureGroupBatches.isEmpty)
  }

  @Test("취소된 Task 에서 캡처 묶음 소급 배치를 부르면 대상을 그대로 두고 진행률 없이 취소로 멈춘다")
  func captureGroupBackfillRethrowsCancellation() async {
    let attempts = CallCount()
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedShopping($0) },
      captureGroup: CaptureGroupStoreOptions(onSave: { _ in attempts.record() })
    )

    let (stop, remaining, reportCount) = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      var run = IndexingRun(
        photoLibrary: fixture.photoLibrary,
        imageAnalysis: fixture.analysis,
        photoStore: fixture.store,
        classifier: fixture.classifier,
        calendar: Fixture.seoulCalendar,
        batchSize: 1,
        textBatchSize: 1
      )
      run.assets = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
      run.pendingCaptureGroupIDs = ["a", "b"]
      var reportCount = 0
      do throws(IndexingStop) {
        try await run.extractCaptureGroupBatch { _ in reportCount += 1 }
        return (IndexingStop?.none, run.pendingCaptureGroupIDs, reportCount)
      } catch {
        return (IndexingStop?.some(error), run.pendingCaptureGroupIDs, reportCount)
      }
    }.value

    #expect(stop == .cancelled)
    #expect(remaining == ["a", "b"])
    #expect(reportCount == 0)
    #expect(attempts.calls == 0)
    #expect(fixture.store.savedCaptureGroupBatches.isEmpty)
  }
}
