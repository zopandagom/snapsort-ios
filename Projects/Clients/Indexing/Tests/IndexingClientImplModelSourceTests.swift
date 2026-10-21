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

/// 추출 값의 필드별 출처: 2단계·소급 보강이 모델로 채운 필드를 저장소에 넘기고, 출처 없이 마친 옛 행(`.sourcesUnknown`)은
/// 소급 보강이 모델 없이 출처만 정한다. 사용 여부는 인덱서의 어느 저장에도 남는다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplModelSourceTests {
  @Test("2단계 저장은 모델로 채운 필드를 출처로 넘기고 규칙 값만이면 빈 출처다")
  func savesModelFilledFieldsFromTextPass() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let filled = ImageAsset.stub(id: "filled", creationDate: date(month: 10, day: 2), isScreenshot: true)
    let rules = ImageAsset.stub(id: "rules", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [filled, rules],
      stored: [pending(filled), pending(rules)],
      text: ["filled": modelFillText, "rules": gifticonText],
      classifier: classifier
    )

    await fixture.runToEnd()

    var saved: [ImageAsset.ID: GifticonInfo] = [:]
    for image in fixture.store.savedBatches.joined() {
      saved[image.id] = image.gifticon
    }
    #expect(saved["filled"]?.modelFilledFields == [.expiryDate])
    #expect(saved["rules"]?.modelFilledFields == [])
    #expect(fixture.storedImages["filled"]?.gifticon == modelFilledGifticon)
    #expect(fixture.storedImages["rules"]?.gifticon == extractedGifticon)
  }

  @Test("소급 보강 결과는 모델로 채운 필드를 출처로 싣는다")
  func sendsModelFilledFieldsFromBackfill() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [recognizedGifticon(coupon, text: modelFillText, gifticon: modelFillRules)],
      classifier: classifier
    )

    await fixture.runToEnd()

    guard case let .filled(info)? = fixture.store.savedModelFillBatches.only?["coupon"] else {
      Issue.record("보강 결과가 filled 가 아니다")
      return
    }
    #expect(info.modelFilledFields == [.expiryDate])
  }

  @Test(
    "출처를 모르는 옛 마침 행은 모델을 쓸 수 있든 없든 부르지 않고, 규칙 값과 다른 필드만 모델 출처로 정해 마친다",
    arguments: ModelMode.allCases
  )
  func resolvesSourcesWithoutModel(mode: ModelMode) async throws {
    let classifier = mode.classifier
    // 최신순이라 연속 실패 차단 모드에서는 실패하는 세 행을 먼저 보강해 모델을 멈춘 뒤 옛 마침 행을 본다.
    let failing = (1 ... 3).map { ImageAsset.stub(
      id: "f\($0)",
      creationDate: date(month: 9, day: $0),
      isScreenshot: true
    ) }
    let model = ImageAsset.stub(id: "model", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let rules = ImageAsset.stub(id: "rules", creationDate: date(month: 5, day: 1), isScreenshot: true)
    // 저장된 값은 지금 보강 버전으로 마친 값이다: 만료일은 모델이, 교환처는 규칙이 찾았다.
    let storedModelValue = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "카페")
    let failingRows = mode == .suspended
      ? failing.map { recognizedGifticon($0, text: modelFillText, gifticon: modelFillRules) }
      : []
    let fixture = Fixture(
      library: (mode == .suspended ? failing : []) + [model, rules],
      stored: failingRows + [
        recognizedGifticon(model, text: modelFillText, gifticon: storedModelValue, modelFill: .sourcesUnknown),
        recognizedGifticon(rules, text: gifticonText, gifticon: extractedGifticon, modelFill: .sourcesUnknown),
      ],
      classifier: classifier
    )
    let expiryDate = try #require(LocalDate(year: 2026, month: 12, day: 31))
    let expiriesBefore = try await fixture.store.upcomingGifticonExpiries(from: expiryDate)

    await fixture.runToEnd()

    let results = fixture.store.savedModelFillBatches.reduce(into: [:]) { $0.merge($1) { first, _ in first } }
    #expect(results["model"] == .resolvedSources(modelFilledGifticon))
    #expect(results["rules"] == .resolvedSources(extractedGifticon))
    let images = fixture.storedImages
    #expect(images["model"]?.gifticon == modelFilledGifticon)
    #expect(images["model"]?.gifticonModelFill == .done)
    #expect(images["rules"]?.gifticon == extractedGifticon)
    #expect(images["rules"]?.gifticonModelFill == .done)
    // 값을 바꾸지 않으므로 만료 예정(알림)도 그대로다.
    #expect(try await fixture.store.upcomingGifticonExpiries(from: expiryDate) == expiriesBefore)
    #expect(expiriesBefore.map(\.imageID) == ["model", "rules"])
    // 모델은 실패하는 행에만 불렀다(옛 마침 행에는 부르지 않는다).
    #expect(classifier.requests.count == (mode == .suspended ? 3 : 0))
  }

  @Test("보강 저장소 호출이 실패하면 이번 실행 소급만 멈추고 옛 마침 행은 값 그대로 출처를 모르는 채 남는다")
  func keepsSourcesUnknownWhenModelFillStoreFails() async {
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let next = ImageAsset.stub(id: "next", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let stored = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "카페")
    let fixture = Fixture(
      library: [coupon, next],
      stored: [
        recognizedGifticon(coupon, text: modelFillText, gifticon: stored, modelFill: .sourcesUnknown),
        pending(next),
      ],
      text: ["next": receiptText],
      modelFillError: .failed
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedModelFillBatches.isEmpty)
    #expect(fixture.storedImages["coupon"]?.gifticon == stored)
    #expect(fixture.storedImages["coupon"]?.gifticonModelFill == .sourcesUnknown)
    // 글자 읽기는 이어 간다.
    #expect(fixture.storedImages["next"]?.textLines == ocrLines(receiptText))
  }

  @Test("같은 배치에서 모델 응답 도중 취소되면 옛 마침 행의 출처도 저장하지 않는다")
  func dropsSourceResolutionOnCancel() async {
    let consumer = ConsumerTask()
    let classifier = ClassifierClientFake(
      classify: { _ in .success([]) },
      extractGifticon: { _ in
        consumer.cancel()
        while !Task.isCancelled {
          await Task.yield()
        }
        return .success(modelExpiryAnswer)
      }
    )
    // 최신순이라 출처를 정하는 "old" 가 먼저 끝나지만 같은 배치라 저장하지 않는다.
    let old = ImageAsset.stub(id: "old", creationDate: date(month: 5, day: 2), isScreenshot: true)
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [old, coupon],
      stored: [
        recognizedGifticon(old, text: gifticonText, gifticon: extractedGifticon, modelFill: .sourcesUnknown),
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
    #expect(fixture.storedImages["old"]?.gifticonModelFill == .sourcesUnknown)
  }

  @Test("사용함인 기프티콘은 2단계 재저장·소급 추출·소급 보강 뒤에도 사용함이다")
  func keepsUsageAcrossIndexerWrites() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let ocr = ImageAsset.stub(id: "ocr", creationDate: date(month: 10, day: 3), isScreenshot: true)
    let extract = ImageAsset.stub(id: "extract", creationDate: date(month: 10, day: 2), isScreenshot: true)
    let fill = ImageAsset.stub(id: "fill", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [ocr, extract, fill],
      stored: [
        // 글자를 읽기 전에 기프티콘으로 저장된 행(2단계가 같은 행을 다시 저장한다).
        IndexedImage(asset: ocr, labels: defaultLabels, textRecognition: .pending, categories: [.gifticon]),
        recognizedGifticon(extract, text: gifticonText),
        recognizedGifticon(fill, text: modelFillText, gifticon: modelFillRules),
      ],
      text: ["ocr": gifticonText],
      usedIDs: ["ocr", "extract", "fill"],
      classifier: classifier
    )

    await fixture.runToEnd()

    let savedIDs = Set(fixture.store.savedBatches.joined().map(\.id))
    let extractedIDs = Set(fixture.store.savedGifticonBatches.flatMap(\.keys))
    let filledIDs = Set(fixture.store.savedModelFillBatches.flatMap(\.keys))
    #expect(savedIDs.contains("ocr"))
    #expect(extractedIDs.contains("extract"))
    #expect(filledIDs.contains("fill"))
    #expect(fixture.store.usedIDs == ["ocr", "extract", "fill"])
    #expect(fixture.storedImages["ocr"]?.gifticon == extractedGifticon)
  }
}

/// 소급 보강 때 모델 상태.
enum ModelMode: CaseIterable {
  /// 쓸 수 있다(답을 정해 둔다).
  case available
  /// 쓸 수 없다.
  case unavailable
  /// 쓸 수 있지만 잇달아 실패해 이번 실행에서 멈춘다.
  case suspended

  var classifier: ClassifierClientFake {
    switch self {
    case .available: ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    case .unavailable: ClassifierClientFake(isModelAvailable: false, extractResult: .success(modelExpiryAnswer))
    case .suspended: ClassifierClientFake(extractResult: .failure(.failed))
    }
  }
}
