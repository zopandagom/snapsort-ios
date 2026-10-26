import Core
import Foundation
import ImageAnalysisInterface
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 1단계 특징 벡터: 벡터 대상 사진은 분류와 같은 썸네일로 벡터를 만들어 같은 저장에 넣고, 실패해도 분류는 저장한다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplFeaturePrintTests {
  @Test("벡터 대상 사진만 분류와 같은 썸네일로 벡터를 만들어 같은 저장에 넣는다")
  func phaseOneComputesForTargets() async {
    let photo = cameraPhoto("photo", day: 9)
    let screenshot = ImageAsset.stub(id: "shot", creationDate: date(month: 5, day: 8), isScreenshot: true)
    let undated = ImageAsset.stub(id: "undated")
    let text = ImageAsset.stub(id: "text", creationDate: date(month: 5, day: 7))
    let cloud = cameraPhoto("cloud", day: 6)
    let fixture = Fixture(
      library: [photo, screenshot, undated, text, cloud],
      labels: ["photo": photoLabels, "shot": photoLabels, "undated": photoLabels, "cloud": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, localFallbackIDs: ["cloud"])
    )

    await fixture.runToEnd()

    // 첫 저장에 분류와 벡터가 함께 들어 있다.
    #expect(fixture.store.savedBatches.first?.first { $0.id == "photo" }?.featurePrint
      == fixtureFeaturePrint(width: 1))
    #expect(fixture.storedFeaturePrints == ["photo": fixtureFeaturePrint(width: 1)])
    #expect(fixture.featurePrintRequestCount == 1)
    // 썸네일은 장마다 한 번만 읽는다(대체 버전 사진도 같은 실행에서 소급하지 않는다).
    #expect(fixture.thumbnailLoadIDs == ["photo", "shot", "undated", "text", "cloud"])
    #expect(fixture.store.images.count == 5)
    #expect(fixture.store.savedFeaturePrintBatches.isEmpty)
  }

  @Test("벡터를 만들지 못해도 분류를 벡터 없이 저장하고 같은 실행에서 다시 시도하지 않으며, 다음 실행이 소급한다")
  func phaseOneFailureKeepsClassification() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, failures: ["photo"])
    )

    await fixture.runToEnd()

    #expect(fixture.store.images.map(\.categories) == [classifiedPhoto(photo).categories])
    #expect(fixture.storedFeaturePrints.isEmpty)
    #expect(fixture.featurePrintRequestCount == 1)

    let next = Fixture(library: [photo], stored: fixture.store.images, featurePrint: .available)
    await next.runToEnd()

    #expect(next.storedFeaturePrints == ["photo": fixtureFeaturePrint(width: 1)])
    #expect(next.store.savedFeaturePrintBatches == [["photo": fixtureFeaturePrint(width: 1)]])
  }

  @Test("벡터를 쓸 수 없으면 요청·대기 조회·썸네일 다시 읽기를 하지 않고 진행률도 같다")
  func unavailableSkipsEverything() async {
    let stored = cameraPhoto("stored", day: 9)
    let fresh = cameraPhoto("fresh", day: 8)
    let fixture = Fixture(library: [stored, fresh], stored: [classifiedPhoto(stored)], labels: ["fresh": photoLabels])
    let withPrint = Fixture(
      library: [stored, fresh],
      stored: [classifiedPhoto(stored, featurePrint: fixtureFeaturePrint(width: 1))],
      labels: ["fresh": photoLabels]
    )

    let progresses = await fixture.allProgress()
    let progressesWithPrint = await withPrint.allProgress()

    #expect(fixture.featurePrintRequestCount == 0)
    #expect(fixture.store.featurePrintPendingIDsCallCount == 0)
    #expect(fixture.thumbnailLoadIDs == ["fresh"])
    #expect(progresses == progressesWithPrint)
  }

  @Test("벡터 요청이 3번 잇달아 실패하면 이번 실행에서는 더 부르지 않고 분류는 이어 간다")
  func suspendsAfterConsecutiveFailures() async {
    let photos = (1 ... 5).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      featurePrint: FeaturePrintOptions(isAvailable: true, failures: Set(photos.map(\.id)))
    )

    await fixture.runToEnd()

    #expect(fixture.featurePrintRequestCount == 3)
    #expect(fixture.store.images.count == 5)
    #expect(fixture.storedFeaturePrints.isEmpty)
  }

  @Test("성공하면 연속 실패 수를 0 으로 되돌린다")
  func successResetsFailures() async {
    let photos = (1 ... 5).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      featurePrint: FeaturePrintOptions(isAvailable: true, failures: ["p1", "p2", "p4", "p5"])
    )

    await fixture.runToEnd()

    #expect(fixture.featurePrintRequestCount == 5)
    #expect(Set(fixture.storedFeaturePrints.keys) == ["p3"])
  }

  @Test("연속 실패로 멈춘 뒤 전체 다시 비교가 오면 벡터 없이 저장된 사진을 다시 시도한다")
  func reloadAllRetriesAfterSuspension() async {
    let photos = (1 ... 4).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      featurePrint: FeaturePrintOptions(isAvailable: true, failures: Set(photos.map(\.id)))
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let classified = await progress.next { $0.isFinished && $0.indexedCount == 4 }
    fixture.featurePrintFailures.removeAll()
    fixture.photoLibrary.sendReloadAll(imageAssets: photos)
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(classified != nil)
    #expect(fixture.featurePrintRequestCount == 3 + 4)
    #expect(Set(fixture.storedFeaturePrints.keys) == Set(photos.map(\.id)))
  }

  @Test("요청이 시한을 넘겨 쓸 수 없게 되면 그 장은 벡터 없이 저장하고 나머지 장은 요청하지 않는다")
  func unavailableMidRunStopsRequests() async {
    let photos = (1 ... 3).map { cameraPhoto("p\($0)", day: 10 - $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { _, analysis in
        analysis?.makeFeaturePrintUnavailable()
      })
    )

    await fixture.runToEnd()

    #expect(fixture.featurePrintRequestCount == 1)
    #expect(fixture.store.images.count == 3)
    #expect(fixture.storedFeaturePrints.isEmpty)
    #expect(fixture.store.featurePrintPendingIDsCallCount == 1)
  }

  @Test("1단계 벡터 요청 도중 취소되면 그 배치를 저장하지 않는다")
  func cancellationDuringPhaseOne() async {
    let gate = Gate()
    let started = CallCount()
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { _, _ in
        started.record()
        await gate.wait()
      })
    )

    let task = Task { await fixture.runToEnd() }
    while started.calls == 0 {
      await Task.yield()
    }
    // 문은 열지 않는다. 취소가 인덱서 Task 에 닿으면 훅이 기다림을 멈추고 Fake 가 취소를 던진다.
    task.cancel()
    await task.value
    gate.open()

    #expect(fixture.store.savedBatches.isEmpty)
  }
}
