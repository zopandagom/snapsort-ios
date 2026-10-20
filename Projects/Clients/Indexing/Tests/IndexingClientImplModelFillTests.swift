import ClassifierInterface
import ClassifierTesting
import Core
import Foundation
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import IndexingImpl

/// 소급 보강: 보강을 마치지 않은 저장 기프티콘을 2단계 뒤 저장된 줄로 규칙 추출부터 다시 계산해 보강한다.
/// 소급은 진행률·`isFinished` 에 넣지 않으므로, 변경 스트림을 끝낸 뒤 `run()` 스트림이 끝날 때까지 읽는다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplModelFillTests {
  @Test(
    "보강 대기를 2단계 뒤에 소급 보강하고 대상이 비면 진행률을 한 번 보낸다",
    arguments: [IndexingClientImpl.defaultTextBatchSize, 1]
  )
  func backfillsModelFillAfterTextPass(textBatchSize: Int) async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let requestsAtRecognize = Mutex<[Int]>([])
    let coupons = (1 ... 3).map { ImageAsset.stub(
      id: "coupon-\($0)",
      creationDate: date(month: 5, day: $0),
      isScreenshot: true
    ) }
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: coupons + [ocrPending],
      stored: coupons
        .map { recognizedGifticon($0, text: modelFillText, gifticon: modelFillRules) } + [pending(ocrPending)],
      text: ["p": receiptText],
      onRecognize: { _ in
        let count = classifier.requests.count
        requestsAtRecognize.withLock { $0.append(count) }
      },
      classifier: classifier,
      textBatchSize: textBatchSize
    )
    let filledFixture = Fixture(
      library: coupons + [ocrPending],
      stored: coupons.map { recognizedGifticon($0, text: modelFillText, gifticon: modelFillRules, modelFill: .done) }
        + [pending(ocrPending)],
      text: ["p": receiptText],
      textBatchSize: textBatchSize
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await filledFixture.allProgress()

    // 2단계에서 글자를 읽을 때는 아직 모델에 묻지 않았다.
    #expect(requestsAtRecognize.withLock { $0 } == [0])
    #expect(classifier.requests == Array(repeating: .extractGifticon(ocrLines(modelFillText)), count: 3))
    #expect(fixture.store.savedModelFillBatches.reduce(into: [:]) { $0.merge($1) { first, _ in first } } == [
      "coupon-1": .filled(modelFilledGifticon),
      "coupon-2": .filled(modelFilledGifticon),
      "coupon-3": .filled(modelFilledGifticon),
    ])
    #expect(fixture.store.savedModelFillBatches.count == (textBatchSize == 1 ? 3 : 1))
    #expect(fixture.store.images.filter { $0.id != "p" }.allSatisfy {
      $0.gifticon == modelFilledGifticon && $0.gifticonModelFill == .done
    })
    #expect(Array(progresses.dropLast()) == progressesWithoutTargets)
    #expect(progresses.last == progressesWithoutTargets.last)
  }

  @Test("두 값을 찾은 보강 대기 행은 모델 없이 마친다")
  func finishesPendingRowWithBothValuesWithoutModel() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    // 경량 이전 직후의 기존 행(두 값이 있어도 보강 대기).
    let fixture = Fixture(
      library: [coupon],
      stored: [recognizedGifticon(
        coupon,
        text: gifticonText,
        gifticon: extractedGifticon,
        modelFill: .pending(failures: 0)
      )],
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedModelFillBatches == [["coupon": .filled(extractedGifticon)]])
    #expect(fixture.store.images.only?.gifticonModelFill == .done)
    #expect(classifier.requests.isEmpty)
  }

  @Test("모델을 쓸 수 없어도 옛 보강 버전 행은 규칙 값으로 되돌린다")
  func revertsStaleRowWithoutModel() async {
    let classifier = ClassifierClientFake(isModelAvailable: false, extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [recognizedGifticon(coupon, text: modelFillText, gifticon: staleModelGifticon, modelFill: .stale)],
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedModelFillBatches == [["coupon": .deferred(rules: modelFillRules)]])
    let image = fixture.store.images.only
    #expect(image?.gifticon == modelFillRules)
    #expect(image?.gifticonModelFill == .pending(failures: 0))
    #expect(classifier.requests.isEmpty)
  }

  @Test("소급 추출한 기프티콘에 빈 값이 있으면 같은 실행에서 보강한다")
  func fillsBackfilledGifticonInSameRun() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [recognizedGifticon(coupon, text: modelFillText)],
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedGifticonBatches == [["coupon": modelFillRules]])
    #expect(fixture.store.savedModelFillBatches == [["coupon": .filled(modelFilledGifticon)]])
    let image = fixture.store.images.only
    #expect(image?.gifticon == modelFilledGifticon)
    #expect(image?.gifticonModelFill == .done)
  }

  @Test("소급 보강 도중 온 보관함 변경을 배치 경계에서 먼저 반영한다")
  func appliesRemovalBetweenModelFillBatches() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let calls = CallCount()
    let classifier = ClassifierClientFake(
      classify: { _ in .success([]) },
      extractGifticon: { _ in
        if calls.record() == 1 {
          library.current?.sendIncrementalChange(removed: ["b"])
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번. 그 뒤에 답해 다음 배치 경계에서 반영되게 한다.
          await changeRequests.wait(until: 2)
          library.current?.finishImageChanges()
        }
        return .success(modelExpiryAnswer)
      }
    )
    let assets = ["a", "b", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: modelFillText, gifticon: modelFillRules) },
      classifier: classifier,
      textBatchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    for await _ in fixture.indexing.run() {}

    #expect(fixture.store.savedModelFillBatches.map { Set($0.keys) } == [["a"], ["c"]])
    #expect(fixture.store.deletedBatches == [["b"]])
    #expect(fixture.store.images.map(\.id) == ["a", "c"])
    #expect(classifier.requests.count == 2)
  }
}
