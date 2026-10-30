import ClassifierTesting
import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import Synchronization
import Testing
@testable import IndexingImpl

/// BG 모드(앱 비활성 + BG 작업이 실행을 쥠)에서만 다른 동작 (docs/ARCHITECTURE.md §4 인덱싱): 실패를 결과로 굳히지 않고 미루며,
/// Vision 이 잇달아 실패하면 멈춘다. 특징 벡터는 BG 모드에서도 같게 요청하고 이미지 분석에 앱 활성 상태를 알린다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplBackgroundModeTests {
  @Test("BG 모드의 바코드 확인 실패는 바코드 없음으로 저장하지 않고 미뤄 다시 예약하게 한다")
  func defersBarcodeFailure() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      barcode: BarcodeOptions(failures: ["photo"])
    )

    let result = await fixture.runInBackground()

    #expect(result.hasRemainingWork)
    #expect(fixture.store.images.isEmpty)
  }

  @Test("BG 모드에서 사진 조회가 비었는데 저장된 결과가 있으면 지우지 않고 남은 것으로 멈춘다")
  func keepsStoredRowsWhenLibraryReadsEmpty() async {
    let fixture = Fixture(library: [], stored: [indexed("gift")])

    let result = await fixture.runInBackground()

    #expect(result.hasRemainingWork)
    #expect(fixture.store.images.only?.asset.id == indexed("gift").asset.id)
  }

  @Test("BG 모드에서 미룬 장은 다시 활성이 된 새 실행이 앞 모드로 처리한다")
  func retriesDeferredOnActivation() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      barcode: BarcodeOptions(failures: ["photo"])
    )
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)
    _ = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })
    #expect(fixture.store.images.isEmpty)

    indexing.appActivityChanged(isActive: true)
    await eventually { fixture.store.images.count == 1 }

    #expect(fixture.store.images.only?.textRecognition == .notNeeded)
    consumer.cancel()
  }

  @Test("BG 모드에서 분류 보강이 거부되면 규칙 결과로 저장하지 않고 대기로 남긴다")
  func keepsRejectedClassificationPending() async {
    let other = ImageAsset.stub(id: "other", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [other],
      stored: [pending(other)],
      text: ["other": otherOnlyText],
      classifier: ClassifierClientFake(classifyResult: .failure(.rejected))
    )

    let result = await fixture.runInBackground()

    #expect(result.hasRemainingWork)
    #expect(fixture.store.images.only?.textRecognition == .pending)
  }

  @Test("BG 모드에서도 모델을 쓸 수 없으면 규칙 결과로 저장한다")
  func savesRulesWhenModelUnavailable() async {
    let other = ImageAsset.stub(id: "other", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [other],
      stored: [pending(other)],
      text: ["other": otherOnlyText],
      classifier: ClassifierClientFake(classifyResult: .failure(.unavailable))
    )

    let result = await fixture.runInBackground()

    #expect(!result.hasRemainingWork)
    #expect(fixture.store.images.only?.categories == [.other])
    #expect(fixture.store.images.only?.textRecognition == .recognized(ocrLines(otherOnlyText)))
  }

  @Test("BG 모드에서 모델 차단 중에 보강이 필요한 이미지도 대기로 남긴다")
  func defersWhileModelSuspended() async {
    let classifier = ClassifierClientFake(classifyResult: .failure(.rejected))
    let others = (1 ... 5).map { ImageAsset.stub(
      id: "other-\($0)",
      creationDate: date(month: 6, day: $0),
      isScreenshot: true
    ) }
    let fixture = Fixture(
      library: others,
      stored: others.map { pending($0) },
      text: Dictionary(uniqueKeysWithValues: others.map { ($0.id, otherOnlyText) }),
      classifier: classifier
    )

    let result = await fixture.runInBackground()

    #expect(result.hasRemainingWork)
    #expect(classifier.requests.count == IndexingRun.maximumConsecutiveModelFailures)
    #expect(fixture.store.images.allSatisfy { $0.textRecognition == .pending })
  }

  @Test("BG 모드에서 Vision 이 잇달아 실패하면 실행을 멈추고 남은 일로 돌아온다")
  func stopsAfterConsecutiveVisionFailures() async {
    let library = (0 ..< 5).map { ImageAsset.stub(id: "image-\($0)") }
    let fixture = Fixture(library: library, classifyFailures: ["image-0", "image-1", "image-2"])

    let result = await fixture.runInBackground()

    #expect(result.hasRemainingWork)
    #expect(fixture.thumbnailLoadIDs.count == IndexingRun.maxConsecutiveBackgroundVisionFailures)
  }

  @Test("BG 모드에서 Vision 실패 사이에 성공이 있으면 멈추지 않는다")
  func continuesWhenFailuresAreNotConsecutive() async {
    let library = (0 ..< 5).map { ImageAsset.stub(id: "image-\($0)") }
    let fixture = Fixture(library: library, classifyFailures: ["image-0", "image-1", "image-3", "image-4"])

    let result = await fixture.runInBackground()

    #expect(!result.hasRemainingWork)
    #expect(fixture.thumbnailLoadIDs.count == 5)
    #expect(fixture.store.images.map(\.id) == ["image-2"])
  }

  @Test("BG 모드에서도 1단계 특징 벡터를 요청해 같은 저장에 넣고 벡터 대기는 소급한다")
  func requestsFeaturePrintsInBackground() async {
    let fresh = cameraPhoto("fresh", day: 9)
    let old = cameraPhoto("old", day: 8)
    let fixture = Fixture(
      library: [fresh, old],
      stored: [classifiedPhoto(old)],
      labels: ["fresh": photoLabels],
      featurePrint: .available
    )

    _ = await fixture.runInBackground()

    #expect(fixture.storedFeaturePrints["fresh"] != nil)
    #expect(fixture.storedFeaturePrints["old"] != nil)
  }

  @Test("뒤에서 벡터를 쓸 수 없으면 BG 모드는 벡터를 요청하지 않고 다시 예약하지 않으며, 활성이 되면 새 실행이 소급한다")
  func leavesFeaturePrintsForForeground() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      stored: [classifiedPhoto(photo)],
      featurePrint: FeaturePrintOptions(isAvailable: true, isAvailableInBackground: false)
    )
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })

    #expect(!result.hasRemainingWork)
    #expect(fixture.featurePrintRequestCount == 0)

    indexing.appActivityChanged(isActive: true)
    await eventually { fixture.storedFeaturePrints["photo"] != nil }
    consumer.cancel()
  }

  @Test("BG 모드의 벡터 실패는 Vision 연속 실패로 세지 않아 실행을 멈추지 않고 벡터만 이번 실행에서 멈춘다")
  func featurePrintFailuresDoNotStopRun() async {
    let photos = (1 ... 5).map { cameraPhoto("photo-\($0)", day: $0) }
    let fixture = Fixture(
      library: photos,
      stored: photos.map { classifiedPhoto($0) },
      featurePrint: FeaturePrintOptions(isAvailable: true, failures: Set(photos.map(\.id)))
    )

    let result = await fixture.runInBackground()

    #expect(!result.hasRemainingWork)
    #expect(fixture.featurePrintRequestCount == IndexingRun.maximumConsecutiveFeaturePrintFailures)
  }

  @Test("앱 활성 값은 바뀔 때만 순서대로 이미지 분석에 알리고, 활성 전이의 새 실행은 알린 뒤에 벡터를 요청한다")
  func forwardsActivityToImageAnalysis() async {
    let activityAtFeaturePrint = Received<Bool?>()
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { _, analysis in
        activityAtFeaturePrint.append(analysis?.activityChanges.last)
      })
    )
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)
    indexing.appActivityChanged(isActive: true)
    await consumer.waitUntilFinished()
    indexing.appActivityChanged(isActive: false)

    #expect(fixture.analysis.activityChanges == [false, true, false])
    #expect(activityAtFeaturePrint.all == [true])
    consumer.cancel()
  }

  @Test("BG 가 쥔 앞 모드 실행에서 앱이 뒤로 가면 실행은 이어 가고 다음 요청 전에 이미지 분석이 뒤 상태를 안다")
  func continuesHeldRunAfterBackgrounding() async {
    let indexing = Later<IndexingClientImpl>()
    let activityAtFeaturePrint = Received<Bool?>()
    let photos = [cameraPhoto("a", day: 9), cameraPhoto("b", day: 8)]
    let fixture = Fixture(
      library: photos,
      labels: ["a": photoLabels, "b": photoLabels],
      onClassify: { id in
        if id == "a" {
          indexing.current?.appActivityChanged(isActive: false)
        }
      },
      featurePrint: FeaturePrintOptions(isAvailable: true, onFeaturePrint: { _, analysis in
        activityAtFeaturePrint.append(analysis?.activityChanges.last)
      })
    )
    indexing.set(fixture.indexing)

    let result = await indexing.current?.runInBackground(shouldYield: { false }, progress: { _ in })

    #expect(result?.didChangeStore == true)
    #expect(fixture.store.images.count == 2)
    #expect(activityAtFeaturePrint.all == [false, false])
  }
}

extension Fixture {
  /// 앱을 비활성으로 알린 뒤 BG 실행을 할 일이 없어질 때까지 돌린다.
  func runInBackground() async -> IndexingBackgroundResult {
    let indexing = self.indexing
    indexing.appActivityChanged(isActive: false)
    return await indexing.runInBackground(shouldYield: { false }, progress: { _ in })
  }
}
