import ClassifierTesting
import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import Testing
@testable import IndexingImpl

/// 이미지 분석이 분류할 수 없을 때(뒤에서 앞에서 불러 둔 요청이 없거나, 세션이 없고 시한을 넘기고 돌아오지 않은 작업이 둘 이상이라 멈춤,
/// `isClassificationAvailable == false`)의 1단계 미룸 (docs/ARCHITECTURE.md §4 인덱싱): 남은 대상을 저장하지 않고 이번 실행에서 미루고, 글자 읽기는 이어
/// 가며, 다시 예약하지 않는다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClassificationHeldTests {
  @Test("뒤에서 분류할 수 없으면 BG 실행은 분류를 요청하지 않고 미분류 장을 저장하지 않으며, 글자 읽기는 하고 다시 예약하지 않는다")
  func holdsClassificationInBackground() async {
    let photos = (1 ... 3).map { cameraPhoto("photo-\($0)", day: $0) }
    let memo = ImageAsset.stub(id: "memo", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: photos + [memo],
      stored: [pending(memo)],
      text: ["memo": otherOnlyText],
      isClassificationAvailableInBackground: false
    )
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let received = Received<IndexingProgress>()

    let result = await indexing.runInBackground(shouldYield: { false }, progress: { received.append($0) })

    #expect(!result.hasRemainingWork)
    #expect(!fixture.analysis.requests.contains {
      if case .classify = $0 {
        true
      } else {
        false
      }
    })
    #expect(fixture.store.images.map(\.id) == ["memo"])
    #expect(fixture.store.images.only?.textRecognition == .recognized(ocrLines(otherOnlyText)))
    #expect(received.all.last?.skippedCount == 3)
    #expect(received.all.last?.isFinished == true)
    // 미룬 장이 건너뜀이 되어 1단계를 벗어난다(조정자의 장소 회차 신호 전제).
    #expect(received.all.last?.phase != .classifying)
  }

  @Test("1단계에서 미룬 장 수를 BG 통계에 남기고, 이것은 다시 예약할 미룸이 아니다")
  func recordsHeldCount() async {
    let photos = (1 ... 3).map { cameraPhoto("photo-\($0)", day: $0) }
    let fixture = Fixture(library: photos, isClassificationAvailableInBackground: false)
    fixture.analysis.appActivityChanged(isActive: false)
    let events = Received<BackgroundRunEvent>()

    let stop = await Task {
      var run = fixture.indexing.makeRun(environment: RunEnvironment(
        isBackground: { true },
        record: { events.append($0) }
      ))
      run.assets = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
      do throws(IndexingStop) {
        try await run.classifyAll(photos) { _ in }
        return IndexingStop?.none
      } catch {
        return IndexingStop?.some(error)
      }
    }.value

    var stats = BackgroundRunStats()
    for event in events.all {
      stats.add(event)
    }
    #expect(stop == nil)
    #expect(stats.classificationHeld == 3)
    #expect(stats.classified == 0)
    #expect(!stats.hasDeferred)
  }

  @Test("뒤에서 미룬 장은 다시 활성이 된 새 실행이 분류해 저장한다")
  func classifiesHeldOnActivation() async {
    let photos = (1 ... 3).map { cameraPhoto("photo-\($0)", day: $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      isClassificationAvailableInBackground: false
    )
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let consumer = ProgressConsumer(indexing)
    _ = await indexing.runInBackground(shouldYield: { false }, progress: { _ in })
    #expect(fixture.store.images.isEmpty)

    indexing.appActivityChanged(isActive: true)
    await eventually { fixture.store.images.count == 3 }

    #expect(Set(fixture.store.images.map(\.id)) == Set(photos.map(\.id)))
    consumer.cancel()
  }

  @Test("뒤에서 분류하던 중 분류할 수 없게 되면 앞서 분류한 장은 저장하고 나머지는 미룬다")
  func holdsRemainingAfterBecomingUnavailable() async {
    let analysis = Later<ImageAnalysisClientFake>()
    let classified = Received<ImageAsset.ID>()
    let photos = (1 ... 3).map { cameraPhoto("photo-\($0)", day: $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      onClassify: { id in
        classified.append(id)
        analysis.current?.makeClassificationUnavailableInBackground()
      }
    )
    analysis.set(fixture.analysis)

    let result = await fixture.runInBackground()

    #expect(!result.hasRemainingWork)
    #expect(fixture.analysis.requests.count {
      if case .classify = $0 {
        true
      } else {
        false
      }
    } == 1)
    #expect(classified.all.count == 1)
    #expect(fixture.store.images.map(\.id) == classified.all)
  }

  @Test("앞 실행은 이미지 분석이 뒤에서 분류할 수 없어도 모두 분류한다")
  func foregroundIgnoresBackgroundAvailability() async {
    let photos = (1 ... 3).map { cameraPhoto("photo-\($0)", day: $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) }),
      isClassificationAvailableInBackground: false
    )
    let consumer = ProgressConsumer(fixture.indexing)

    await consumer.waitUntilFinished()

    #expect(Set(fixture.store.images.map(\.id)) == Set(photos.map(\.id)))
    #expect(consumer.received.last?.skippedCount == 0)
    consumer.cancel()
  }

  @Test("앞 실행도 이미지 분석이 분류할 수 없으면(세션 없이 돌아오지 않은 작업이 둘 이상이라 멈춤) 분류를 요청하지 않고 미분류 장을 저장하지 않으며 미룬 장으로 끝낸다")
  func holdsClassificationInForegroundWhenUnavailable() async {
    let photos = (1 ... 3).map { cameraPhoto("photo-\($0)", day: $0) }
    let fixture = Fixture(
      library: photos,
      labels: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, photoLabels) })
    )
    fixture.analysis.makeClassificationUnavailable()
    let consumer = ProgressConsumer(fixture.indexing)

    await consumer.waitUntilFinished()

    #expect(!fixture.analysis.requests.contains {
      if case .classify = $0 {
        true
      } else {
        false
      }
    })
    #expect(fixture.store.images.isEmpty)
    #expect(consumer.received.last?.skippedCount == 3)
    #expect(consumer.received.last?.isFinished == true)
    consumer.cancel()
  }
}
