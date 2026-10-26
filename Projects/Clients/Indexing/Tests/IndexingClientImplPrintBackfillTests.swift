import ClassifierTesting
import Core
import Foundation
import ImageAnalysisInterface
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import IndexingImpl

/// 벡터 소급: 지금 버전 벡터가 없는 저장 사진의 썸네일을 2단계 뒤·소급 보강 앞에 다시 읽어 벡터만 저장한다.
/// 소급은 진행률·`isFinished` 에 넣지 않으므로, 변경 스트림을 끝낸 뒤 `run()` 스트림이 끝날 때까지 읽는다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplPrintBackfillTests {
  @Test("벡터 대기 사진의 썸네일을 다시 읽어 벡터만 저장하고, 2단계 뒤·소급 보강 앞에 한다")
  func backfillsAfterTextPassBeforeModelFill() async throws {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let modelRequestsAtFeaturePrint = Mutex<[Int]>([])
    let photos = [cameraPhoto("a", day: 9), cameraPhoto("b", day: 8)]
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 4, day: 1), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: photos + [coupon, ocrPending],
      stored: photos.map { classifiedPhoto($0) } + [
        recognizedGifticon(coupon, text: modelFillText, gifticon: modelFillRules),
        pending(ocrPending),
      ],
      text: ["p": receiptText],
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { _, _ in
        let count = classifier.requests.count
        modelRequestsAtFeaturePrint.withLock { $0.append(count) }
      }),
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.storedFeaturePrints == ["a": fixtureFeaturePrint(width: 1), "b": fixtureFeaturePrint(width: 2)])
    #expect(fixture.store.savedFeaturePrintBatches == [
      ["a": fixtureFeaturePrint(width: 1), "b": fixtureFeaturePrint(width: 2)],
    ])
    #expect(fixture.thumbnailLoadIDs == ["a", "b"])
    // 2단계(글자 읽기)를 먼저 하고, 벡터를 만들 때는 아직 모델에 묻지 않았다.
    let requests = fixture.analysis.requests
    let firstText = try #require(requests.firstIndex(of: .recognizeText))
    let firstFeaturePrint = try #require(requests.firstIndex(of: .featurePrint))
    #expect(firstText < firstFeaturePrint)
    #expect(modelRequestsAtFeaturePrint.withLock { $0 } == [0, 0])
    #expect(classifier.requests.count == 1)
    // 벡터만 바꾼다.
    let expected = classifiedPhoto(photos[0], featurePrint: fixtureFeaturePrint(width: 1))
    #expect(fixture.store.images.first { $0.id == "a" } == expected)
  }

  @Test("소급은 batchSize 장씩 최신부터 하고 배치마다 진행률을 보내지 않으며 대상이 비면 한 번 보낸다", arguments: [1, 2, 50])
  func batchesAndReportsOnce(batchSize: Int) async {
    let photos = (1 ... 5).map { cameraPhoto("p\($0)", day: $0) }
    let fixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0) },
      featurePrint: .available,
      batchSize: batchSize
    )
    let doneFixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0, featurePrint: fixtureFeaturePrint(width: 1)) },
      featurePrint: .available,
      batchSize: batchSize
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await doneFixture.allProgress()

    let expectedBatches = stride(from: 0, to: 5, by: batchSize).map { min(batchSize, 5 - $0) }
    #expect(fixture.store.savedFeaturePrintBatches.map(\.count) == expectedBatches)
    #expect(fixture.thumbnailLoadIDs == ["p5", "p4", "p3", "p2", "p1"])
    #expect(progresses == progressesWithoutTargets + [progressesWithoutTargets.last].compactMap(\.self))
    #expect(doneFixture.featurePrintRequestCount == 0)
  }

  @Test("읽지 못한 장·보관함에 없는 장·대체 버전은 건너뛰고 대기로 남는다")
  func skipsUnreadableAndFallback() async throws {
    let photos = ["ok", "gone", "unavailable", "cloud"].enumerated().map { cameraPhoto($1, day: 9 - $0) }
    let fixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0) },
      loadErrors: ["gone": .notFound, "unavailable": .notAvailableLocally],
      featurePrint: FeaturePrintOptions(isAvailable: true, localFallbackIDs: ["cloud"])
    )

    await fixture.runToEnd()

    #expect(fixture.featurePrintRequestCount == 1)
    #expect(Set(fixture.storedFeaturePrints.keys) == ["ok"])
    #expect(try await fixture.store.featurePrintPendingIDs() == ["gone", "unavailable", "cloud"])
  }

  @Test("벡터를 저장하지 못하면 이번 실행의 벡터 소급만 멈추고 진행률을 한 번 보내며, 분류는 이어 간다")
  func stopsBackfillWhenSaveFails() async {
    let photos = (1 ... 3).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fresh = cameraPhoto("fresh", day: 20)
    let fixture = Fixture(
      library: photos + [fresh],
      stored: photos.map { classifiedPhoto($0) },
      labels: ["fresh": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, saveLimit: 0),
      batchSize: 1
    )
    let doneFixture = Fixture(
      library: photos + [fresh],
      stored: photos.map { classifiedPhoto($0, featurePrint: fixtureFeaturePrint(width: 1)) },
      labels: ["fresh": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, saveLimit: 0),
      batchSize: 1
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await doneFixture.allProgress()

    // 첫 배치에서 저장에 실패해 대상을 비우므로 다음 장을 읽지 않는다.
    #expect(fixture.thumbnailLoadIDs == ["fresh", "p1"])
    #expect(fixture.store.savedFeaturePrintBatches.isEmpty)
    #expect(fixture.store.images.contains { $0.id == "fresh" })
    #expect(progresses == progressesWithoutTargets + [progressesWithoutTargets.last].compactMap(\.self))
  }

  @Test("벡터 대기를 조회하지 못하면 소급 없이 분류는 이어 간다")
  func continuesWhenPendingQueryFails() async {
    let stored = cameraPhoto("stored", day: 9)
    let fresh = cameraPhoto("fresh", day: 8)
    let fixture = Fixture(
      library: [stored, fresh],
      stored: [classifiedPhoto(stored)],
      labels: ["fresh": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, storeError: .failed)
    )

    await fixture.runToEnd()

    #expect(fixture.thumbnailLoadIDs == ["fresh"])
    // 1단계 벡터는 저장소의 벡터 소급 호출이 아니라 save 로 들어간다.
    #expect(Set(fixture.storedFeaturePrints.keys) == ["fresh"])
  }

  @Test("소급 도중 요청이 시한을 넘겨 쓸 수 없게 되면 남은 장은 건너뛰고 대상을 비우며 진행률을 한 번 보낸다")
  func unavailableMidBackfill() async {
    let photos = (1 ... 3).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0) },
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { _, analysis in
        analysis?.makeFeaturePrintUnavailable()
      })
    )
    let doneFixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0, featurePrint: fixtureFeaturePrint(width: 1)) },
      featurePrint: .available
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await doneFixture.allProgress()

    #expect(fixture.featurePrintRequestCount == 1)
    #expect(fixture.thumbnailLoadIDs == ["p1"])
    #expect(fixture.store.savedFeaturePrintBatches.isEmpty)
    #expect(progresses == progressesWithoutTargets + [progressesWithoutTargets.last].compactMap(\.self))
  }

  @Test("증분 삭제는 벡터 소급 대상에서 뺀다")
  func incrementalDeletionRemovesTargets() async {
    let photos = (1 ... 2).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let ocrPending = ImageAsset.stub(id: "ocr", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let fixture = Fixture(
      library: photos + [ocrPending],
      stored: photos.map { classifiedPhoto($0) } + [pending(ocrPending)],
      onRecognize: { _ in
        // 2단계(벡터 소급 앞) 도중 p2 를 지운다. 변경이 수신함에 든 뒤에 OCR 을 끝낸다.
        library.current?.sendIncrementalChange(removed: ["p2"])
        await changeRequests.wait(until: 2)
        library.current?.finishImageChanges()
      },
      featurePrint: .available,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    for await _ in fixture.indexing.run() {}

    #expect(fixture.thumbnailLoadIDs == ["p1"])
    #expect(fixture.store.savedFeaturePrintBatches == [["p1": fixtureFeaturePrint(width: 1)]])
  }

  @Test("취소된 Task 에서 벡터 소급 배치를 부르면 대상을 그대로 두고 진행률 없이 취소로 멈춘다")
  func backfillRethrowsCancellation() async {
    let photos = (1 ... 2).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(library: photos, stored: photos.map { classifiedPhoto($0) }, featurePrint: .available)

    let (stop, remaining, reportCount) = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      var run = fixture.indexing.makeRun()
      run.assets = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
      run.pendingFeaturePrintIDs = ["p1", "p2"]
      var reportCount = 0
      do throws(IndexingStop) {
        try await run.computeFeaturePrintBatch { _ in reportCount += 1 }
        return (IndexingStop?.none, run.pendingFeaturePrintIDs, reportCount)
      } catch {
        return (IndexingStop?.some(error), run.pendingFeaturePrintIDs, reportCount)
      }
    }.value

    #expect(stop == .cancelled)
    #expect(remaining == ["p1", "p2"])
    #expect(reportCount == 0)
    #expect(fixture.featurePrintRequestCount == 0)
    #expect(fixture.store.savedFeaturePrintBatches.isEmpty)
  }

  @Test("벡터 요청 도중 취소되면 그 배치를 저장하지 않고 대상을 그대로 둔다")
  func cancellationDuringBackfillRequest() async {
    let photos = (1 ... 2).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0) },
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { id, _ in
        if id == "p2" {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      })
    )

    let (stop, remaining) = await Task {
      var run = fixture.indexing.makeRun()
      run.assets = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
      run.pendingFeaturePrintIDs = ["p1", "p2"]
      do throws(IndexingStop) {
        try await run.computeFeaturePrintBatch { _ in }
        return (IndexingStop?.none, run.pendingFeaturePrintIDs)
      } catch {
        return (IndexingStop?.some(error), run.pendingFeaturePrintIDs)
      }
    }.value

    #expect(stop == .cancelled)
    #expect(remaining == ["p1", "p2"])
    #expect(fixture.featurePrintRequestCount == 2)
    #expect(fixture.store.savedFeaturePrintBatches.isEmpty)
  }
}
