import ClassifierInterface
import ClassifierTesting
import Core
import Foundation
import IndexingInterface
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 시스템 거부(`ClassifierError.rejected`): 입력과 관계없이 시스템이 받지 않은 요청은 행 실패로 세지 않아 빈 필드가 마침으로 굳지 않고,
/// 연속 실패 차단에는 센다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplModelRejectionTests {
  @Test("시스템 거부는 실패로 세지 않고 보강 대기로 둔다")
  func keepsRejectedGifticonPending() async {
    let classifier = ClassifierClientFake(extractResult: .failure(.rejected))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [pending(coupon)],
      text: ["coupon": modelFillText],
      classifier: classifier
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.gifticon == modelFillRules)
    #expect(image?.gifticonModelFill == .pending(failures: 0))
    #expect(classifier.requests == [.extractGifticon(ocrLines(modelFillText))])
  }

  @Test("시스템 거부가 연속 3번이면 이번 실행에서 모델을 멈춘다")
  func suspendsModelAfterConsecutiveRejections() async {
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

    let last = await fixture.runToEnd()

    #expect(classifier.requests == Array(repeating: .classify(ocrLines(otherOnlyText)), count: 3))
    #expect(last?.recognizedTextCount == 5)
    #expect(fixture.store.images.allSatisfy { $0.categories == [.other] })
  }

  @Test("소급 보강의 시스템 거부는 실패를 세지 않고 옛 보강 버전만 되돌린다")
  func revertsOnlyStaleRowOnRejection() async {
    let classifier = ClassifierClientFake(extractResult: .failure(.rejected))
    let assets = ["a", "stale", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: [
        recognizedGifticon(assets[0], text: modelFillText, gifticon: modelFillRules),
        recognizedGifticon(assets[1], text: modelFillText, gifticon: staleModelGifticon, modelFill: .stale),
        recognizedGifticon(assets[2], text: modelFillText, gifticon: modelFillRules),
      ],
      classifier: classifier
    )

    await fixture.runToEnd()

    // 거부 뒤에도 배치의 다음 행을 계속 묻는다(쓸 수 없음과 다르다).
    #expect(classifier.requests == Array(repeating: .extractGifticon(ocrLines(modelFillText)), count: 3))
    #expect(fixture.store.savedModelFillBatches == [["stale": .deferred(rules: modelFillRules)]])
    let images = fixture.storedImages
    #expect(images["a"]?.gifticonModelFill == .pending(failures: 0))
    #expect(images["c"]?.gifticonModelFill == .pending(failures: 0))
    #expect(images["stale"]?.gifticon == modelFillRules)
    #expect(images["stale"]?.gifticonModelFill == .pending(failures: 0))
  }

  @Test("시스템 거부가 세 번 와도 빈 만료일이 마침으로 굳지 않는다")
  func rejectionsDoNotFinishEmptyExpiry() async {
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    var stored = [recognizedGifticon(coupon, text: modelFillText, gifticon: modelFillRules)]
    for _ in 1 ... 3 {
      let rejecting = ClassifierClientFake(extractResult: .failure(.rejected))
      let run = Fixture(library: [coupon], stored: stored, classifier: rejecting)
      await run.runToEnd()
      #expect(rejecting.requests.count == 1)
      #expect(run.store.images.only?.gifticonModelFill == .pending(failures: 0))
      stored = run.store.images
    }

    let answering = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let next = Fixture(library: [coupon], stored: stored, classifier: answering)
    await next.runToEnd()

    let image = next.store.images.only
    #expect(image?.gifticon == modelFilledGifticon)
    #expect(image?.gifticonModelFill == .done)
  }
}
