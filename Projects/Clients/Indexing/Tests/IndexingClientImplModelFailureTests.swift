import ClassifierInterface
import ClassifierTesting
import Core
import Foundation
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 언어 모델 보강의 실패: 모델이 실패하거나 쓸 수 없게 돼도, 보강 저장소 호출이 실패해도 인덱싱은 규칙 결과로 이어 가고,
/// 모델 응답 도중 취소면 그 배치를 저장하지 않고 멈춘다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplModelFailureTests {
  @Test("모델 오류면 규칙 결과로 저장하고 실패를 하나 센다")
  func storesRuleResultsOnModelFailure() async {
    let classifier = ClassifierClientFake(classifyResult: .failure(.failed), extractResult: .failure(.failed))
    let other = ImageAsset.stub(id: "other", creationDate: date(month: 10, day: 2), isScreenshot: true)
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [other, coupon],
      stored: [pending(other), pending(coupon)],
      text: ["other": otherOnlyText, "coupon": modelFillText],
      classifier: classifier
    )

    await fixture.runToEnd()

    let images = fixture.storedImages
    #expect(images["other"]?.categories == [.other])
    #expect(images["coupon"]?.gifticon == modelFillRules)
    #expect(images["coupon"]?.gifticonModelFill == .pending(failures: 1))
    #expect(classifier.requests.count == 2)
  }

  @Test("모델이 연속 3번 실패하면 이번 실행에서는 더 부르지 않는다")
  func suspendsModelAfterConsecutiveFailures() async {
    let classifier = ClassifierClientFake(classifyResult: .failure(.failed), extractResult: .failure(.failed))
    let others = (1 ... 5).map { ImageAsset.stub(
      id: "other-\($0)",
      creationDate: date(month: 6, day: $0),
      isScreenshot: true
    ) }
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: others + [coupon],
      stored: others.map { pending($0) } + [recognizedGifticon(coupon, text: modelFillText, gifticon: modelFillRules)],
      text: Dictionary(uniqueKeysWithValues: others.map { ($0.id, otherOnlyText) }),
      classifier: classifier
    )

    let last = await fixture.runToEnd()

    #expect(classifier.requests == Array(repeating: .classify(ocrLines(otherOnlyText)), count: 3))
    #expect(last?.recognizedTextCount == 5)
    #expect(fixture.store.images.filter { $0.id != "coupon" }.allSatisfy { $0.categories == [.other] })
    // 소급 보강 대상은 모델 없이 건너뛰어(보강 대기라 쓸 것이 없다) 그대로 보강 대기다.
    #expect(fixture.store.savedModelFillBatches.isEmpty)
    #expect(fixture.storedImages["coupon"]?.gifticonModelFill == .pending(failures: 0))
  }

  @Test("연속 실패로 모델을 멈춘 뒤 전체 다시 비교(.reloadAll)가 오면 모델을 다시 쓴다")
  func resumesModelAfterReloadAll() async {
    let classifier = ClassifierClientFake(classifyResult: .failure(.failed), extractResult: .failure(.failed))
    let others = (1 ... 4).map { ImageAsset.stub(
      id: "other-\($0)",
      creationDate: date(month: 6, day: $0),
      isScreenshot: true
    ) }
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let newImage = ImageAsset.stub(id: "new", creationDate: date(month: 7, day: 1), isScreenshot: true)
    let library = others + [coupon]
    let fixture = Fixture(
      library: library,
      loadable: [newImage],
      stored: others.map { pending($0) } + [recognizedGifticon(
        coupon,
        text: modelFillText,
        gifticon: modelFillRules,
        modelFill: .pending(failures: 1)
      )],
      text: Dictionary(uniqueKeysWithValues: (others + [newImage]).map { ($0.id, otherOnlyText) }),
      classifier: classifier
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let suspended = await progress.next { $0.isFinished && $0.recognizedTextCount == 4 }
    // 4장째부터 모델을 부르지 않았고, 소급 보강 대상도 모델에 묻지 않는다.
    let requestsBeforeReload = classifier.requests
    fixture.photoLibrary.sendReloadAll(imageAssets: [newImage] + library)
    let reloaded = await progress.next { $0.isFinished && $0.recognizedTextCount == 5 }
    fixture.photoLibrary.finishImageChanges()
    while await progress.next() != nil {}

    #expect(suspended != nil)
    #expect(reloaded != nil)
    #expect(requestsBeforeReload == Array(repeating: .classify(ocrLines(otherOnlyText)), count: 3))
    let lines = ocrLines(otherOnlyText)
    // 다시 비교한 뒤 새 이미지의 2단계와 실패 수 한도 미만 행의 소급 보강이 다시 모델에 묻는다.
    #expect(classifier
      .requests == Array(repeating: .classify(lines), count: 4) + [.extractGifticon(ocrLines(modelFillText))])
    #expect(fixture.storedImages["coupon"]?.gifticonModelFill == .pending(failures: 2))
    #expect(fixture.store.savedModelFillBatches == [["coupon": .failed(rules: modelFillRules)]])
  }

  @Test("소급 보강 중 모델을 쓸 수 없게 되면 모델이 필요한 행은 건너뛴다")
  func skipsModelFillWhenModelBecomesUnavailable() async {
    let classifier = Later<ClassifierClientFake>()
    let fake = ClassifierClientFake(
      classify: { _ in .success([]) },
      extractGifticon: { _ in
        // 응답 도중 쓸 수 없게 됐다(구현은 오류 뒤 쓸 수 있음을 다시 물어 unavailable 로 바꾼다).
        classifier.current?.setModelAvailable(false)
        return .failure(.unavailable)
      }
    )
    classifier.set(fake)
    let assets = ["a", "b", "stale"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: [
        recognizedGifticon(assets[0], text: modelFillText, gifticon: modelFillRules),
        recognizedGifticon(assets[1], text: modelFillText, gifticon: modelFillRules),
        recognizedGifticon(assets[2], text: modelFillText, gifticon: staleModelGifticon, modelFill: .stale),
      ],
      classifier: fake
    )

    await fixture.runToEnd()

    #expect(fake.requests == [.extractGifticon(ocrLines(modelFillText))])
    // 옛 보강 버전 행만 규칙 값으로 되돌리고, 보강 대기 행은 이미 규칙 값이라 쓰지 않는다. 실패로 세지 않는다.
    #expect(fixture.store.savedModelFillBatches == [["stale": .deferred(rules: modelFillRules)]])
    let images = fixture.storedImages
    #expect(images["a"]?.gifticonModelFill == .pending(failures: 0))
    #expect(images["b"]?.gifticonModelFill == .pending(failures: 0))
    #expect(images["stale"]?.gifticon == modelFillRules)
    #expect(images["stale"]?.gifticonModelFill == .pending(failures: 0))
  }

  @Test("모델이 실패한 옛 보강 버전 행은 규칙 값으로 되돌리고 실패를 센다")
  func revertsStaleRowOnModelFailure() async {
    let classifier = ClassifierClientFake(extractResult: .failure(.failed))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [recognizedGifticon(coupon, text: modelFillText, gifticon: staleModelGifticon, modelFill: .stale)],
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedModelFillBatches == [["coupon": .failed(rules: modelFillRules)]])
    let image = fixture.store.images.only
    #expect(image?.gifticon == modelFillRules)
    #expect(image?.gifticonModelFill == .pending(failures: 1))
  }

  @Test("보강 대상 조회·저장이 실패해도 분류·글자 읽기는 이어 간다")
  func continuesIndexingWhenModelFillStoreFails() async {
    // 조회 실패: 다시 비교의 보강 대상 조회가 실패해도 2단계를 한다.
    let queryClassifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let queryFixture = Fixture(
      library: [coupon, ocrPending],
      stored: [recognizedGifticon(coupon, text: modelFillText, gifticon: modelFillRules), pending(ocrPending)],
      text: ["p": receiptText],
      modelFillError: .failed,
      classifier: queryClassifier
    )

    await queryFixture.runToEnd()

    #expect(queryFixture.storedImages["p"]?.categories == [.receipt])
    #expect(queryClassifier.requests.isEmpty)
    #expect(queryFixture.storedImages["coupon"]?.gifticonModelFill == .pending(failures: 0))

    // 저장 실패: 소급 추출이 더한 보강 대상의 저장이 실패해도, 그 뒤 온 새 사진을 분류한다.
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let newPhoto = ImageAsset.stub(id: "n", creationDate: date(month: 7, day: 1), coordinate: seoul)
    let saveClassifier = ClassifierClientFake(
      classify: { _ in .success([]) },
      extractGifticon: { _ in
        library.current?.sendIncrementalChange(inserted: [newPhoto])
        await changeRequests.wait(until: 2)
        library.current?.finishImageChanges()
        return .success(modelExpiryAnswer)
      }
    )
    let saveFixture = Fixture(
      library: [coupon],
      loadable: [newPhoto],
      stored: [recognizedGifticon(coupon, text: modelFillText)],
      labels: ["n": photoLabels],
      modelFillError: .failed,
      classifier: saveClassifier,
      changeRequests: changeRequests
    )
    library.set(saveFixture.photoLibrary)

    for await _ in saveFixture.indexing.run() {}

    #expect(saveClassifier.requests.count == 1)
    #expect(saveFixture.store.savedModelFillBatches.isEmpty)
    #expect(saveFixture.storedImages["n"] != nil)
    #expect(saveFixture.storedImages["coupon"]?.gifticon == modelFillRules)
  }

  @Test("모델 응답 도중 취소되면 그 배치를 저장하지 않는다")
  func dropsModelFillBatchOnCancel() async {
    let consumer = ConsumerTask()
    let classifier = ClassifierClientFake(
      classify: { _ in .success([]) },
      extractGifticon: { _ in
        consumer.cancel()
        // 구독이 끝나 인덱싱 Task 가 취소될 때까지 답하지 않는다.
        while !Task.isCancelled {
          await Task.yield()
        }
        return .success(modelExpiryAnswer)
      }
    )
    // 최신순이라 모델 없이 마치는 "done" 의 결과가 먼저 정해지지만, 같은 배치라 저장하지 않는다.
    let done = ImageAsset.stub(id: "done", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [done, coupon],
      stored: [
        recognizedGifticon(done, text: gifticonText, gifticon: extractedGifticon, modelFill: .pending(failures: 0)),
        recognizedGifticon(coupon, text: modelFillText, gifticon: modelFillRules),
      ],
      classifier: classifier
    )

    consumer.start {
      for await _ in fixture.indexing.run() {}
    }
    await consumer.wait()
    while fixture.photoLibrary.imageChangesSubscriberCount > 0 {
      await Task.yield()
    }

    #expect(classifier.requests.count == 1)
    #expect(fixture.store.savedModelFillBatches.isEmpty)
    #expect(fixture.store.images.allSatisfy { $0.gifticonModelFill == .pending(failures: 0) })
  }

  @Test("2단계 분류 중 모델 응답이 취소되면 그 배치를 저장하지 않는다")
  func dropsTextBatchOnCancelDuringClassify() async {
    let consumer = ConsumerTask()
    let classifier = ClassifierClientFake(
      classify: { _ in
        consumer.cancel()
        while !Task.isCancelled {
          await Task.yield()
        }
        return .success([.receipt])
      },
      extractGifticon: { _ in .success(modelExpiryAnswer) }
    )
    // 같은 배치에서 앞서 읽은 영수증, 그 뒤 모델에 묻는 기타뿐인 이미지.
    let receipt = ImageAsset.stub(id: "receipt", creationDate: date(month: 6, day: 2), isScreenshot: true)
    let other = ImageAsset.stub(id: "other", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [receipt, other],
      stored: [pending(receipt), pending(other)],
      text: ["receipt": receiptText, "other": otherOnlyText],
      classifier: classifier
    )

    consumer.start {
      for await _ in fixture.indexing.run() {}
    }
    await consumer.wait()
    while fixture.photoLibrary.imageChangesSubscriberCount > 0 {
      await Task.yield()
    }

    #expect(classifier.requests == [.classify(ocrLines(otherOnlyText))])
    #expect(fixture.store.savedBatches.isEmpty)
    #expect(fixture.store.images.allSatisfy { $0.textRecognition == .pending })
  }
}
