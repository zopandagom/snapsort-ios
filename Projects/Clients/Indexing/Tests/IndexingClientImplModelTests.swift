import ClassifierInterface
import ClassifierTesting
import Core
import Foundation
import IndexingInterface
import PhotoLibraryInterface
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 언어 모델 보강: 2단계에서 기타뿐인 이미지의 분류와 기프티콘 빈 필드를 보강한다(소급 보강은 IndexingClientImplModelFillTests).
/// 모델 답은 Core 가 원문으로 확인한 것만 저장한다. 실제 모델은 부르지 않고 Fake 의 정해 둔 답을 쓴다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplModelTests {
  @Test("모델을 쓸 수 없으면 규칙 결과 그대로 저장하고 보강 대기로 둔다")
  func storesRuleResultsWhenModelUnavailable() async {
    let classifier = ClassifierClientFake(
      isModelAvailable: false,
      classifyResult: .success([.receipt]),
      extractResult: .success(modelExpiryAnswer)
    )
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
    #expect(images["coupon"]?.gifticonModelFill == .pending(failures: 0))
    #expect(classifier.requests.isEmpty)
    #expect(fixture.store.savedModelFillBatches.isEmpty)
  }

  @Test("규칙이 못 찾은 만료일을 확인된 모델 값으로 채운다")
  func fillsExpiryWithVerifiedModelAnswer() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [pending(coupon)],
      text: ["coupon": modelFillText],
      classifier: classifier
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.gifticon == modelFilledGifticon)
    #expect(image?.gifticonModelFill == .done)
    #expect(classifier.requests == [.extractGifticon(ocrLines(modelFillText))])
  }

  @Test("확인되지 않은 모델 값은 저장하지 않고 보강을 마친다")
  func dropsUnverifiedModelAnswer() async {
    // 원문에 없는 날짜·상호(모델이 지어낸 값).
    let classifier = ClassifierClientFake(extractResult: .success(GifticonModelAnswer(
      expiryText: "2025.01.01",
      redemptionPlace: "롯데월드"
    )))
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
    #expect(image?.gifticonModelFill == .done)
    #expect(classifier.requests.count == 1)
  }

  @Test("규칙이 두 값을 찾으면 모델을 부르지 않는다")
  func skipsModelWhenRulesFindBoth() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [pending(coupon)],
      text: ["coupon": gifticonText],
      classifier: classifier
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.gifticon == extractedGifticon)
    #expect(image?.gifticonModelFill == .done)
    #expect(classifier.requests.isEmpty)
    #expect(fixture.store.savedModelFillBatches.isEmpty)
  }

  @Test("기타뿐인 이미지에 근거 있는 정보형을 더한다")
  func addsGroundedInformationCategory() async {
    // 영수증은 키워드("영수증")가 있고 지도는 근거가 없다.
    let classifier = ClassifierClientFake(classifyResult: .success([.receipt, .map]))
    let other = ImageAsset.stub(id: "other", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [other],
      stored: [pending(other)],
      text: ["other": otherOnlyText],
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.store.images.only?.categories == [.receipt])
    #expect(classifier.requests == [.classify(ocrLines(otherOnlyText))])
  }

  @Test("글자가 없는 기프티콘은 모델을 부르지 않고 보강을 마친다")
  func finishesGifticonWithoutTextWithoutModel() async {
    let classifier = ClassifierClientFake(extractResult: .success(modelExpiryAnswer))
    let couponLabels = [ImageLabel(identifier: "coupon", confidence: 0.9)]
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    // 라벨만으로 기프티콘이 되고 OCR 은 글자를 읽지 못했다. 모델이 대조할 원문이 없다.
    let fixture = Fixture(
      library: [coupon],
      stored: [pending(coupon, labels: couponLabels)],
      labels: ["coupon": couponLabels],
      classifier: classifier
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.categories.contains(.gifticon) == true)
    #expect(image?.gifticon == GifticonInfo(expiryDate: nil, redemptionPlace: nil))
    #expect(image?.gifticonModelFill == .done)
    #expect(classifier.requests.isEmpty)
  }

  @Test("기타가 아닌 이미지는 모델로 분류하지 않는다")
  func skipsModelForRuleCategorizedImage() async {
    let classifier = ClassifierClientFake(classifyResult: .success([.gifticon]))
    let receipt = ImageAsset.stub(id: "receipt", creationDate: date(month: 10, day: 2), isScreenshot: true)
    let empty = ImageAsset.stub(id: "empty", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [receipt, empty],
      stored: [pending(receipt), pending(empty)],
      text: ["receipt": receiptText],
      classifier: classifier
    )

    await fixture.runToEnd()

    let images = fixture.storedImages
    #expect(images["receipt"]?.categories == [.receipt])
    // 글자가 없으면 기타여도 모델에 묻지 않는다.
    #expect(images["empty"]?.categories == [.other])
    #expect(classifier.requests.isEmpty)
  }

  @Test("모델이 기프티콘을 더하면 추출·보강해 함께 저장한다")
  func extractsGifticonAddedByModel() async {
    let classifier = ClassifierClientFake(
      classifyResult: .success([.gifticon]),
      extractResult: .success(modelExpiryAnswer)
    )
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [coupon],
      stored: [pending(coupon)],
      text: ["coupon": modelOnlyGifticonText],
      classifier: classifier
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.categories == [.gifticon])
    #expect(image?.gifticon == GifticonInfo(
      expiryDate: LocalDate(year: 2026, month: 12, day: 31),
      redemptionPlace: nil,
      modelFilledFields: [.expiryDate]
    ))
    #expect(image?.gifticonModelFill == .done)
    let lines = ocrLines(modelOnlyGifticonText)
    #expect(classifier.requests == [.classify(lines), .extractGifticon(lines)])
  }
}

// 모델 보강 테스트(IndexingClientImplModelTests·IndexingClientImplModelFillTests·IndexingClientImplModelFailureTests) 공통 준비.

/// 교환처 라벨과 키워드 두 개로 규칙이 기프티콘·교환처를 찾고, 만료일은 규칙 라벨이 아닌 영문 단서 뒤에 있어 모델로만 채우는 줄.
let modelFillText = ["교환처 카페", "모바일 상품권", "Valid until 2026.12.31"]
/// `modelFillText` 의 규칙 추출 값.
let modelFillRules = GifticonInfo(expiryDate: nil, redemptionPlace: "카페")
/// `modelFillText` 를 `modelExpiryAnswer` 로 보강한 값. 만료일은 모델이 채웠다.
let modelFilledGifticon = GifticonInfo(
  expiryDate: LocalDate(year: 2026, month: 12, day: 31),
  redemptionPlace: "카페",
  modelFilledFields: [.expiryDate]
)
/// 원문 그대로의 만료일 답.
let modelExpiryAnswer = GifticonModelAnswer(expiryText: "2026.12.31", redemptionPlace: nil)
/// 옛 보강 버전으로 받은 모델 값이 남은 추출 값(`.stale` 행).
let staleModelGifticon = GifticonInfo(expiryDate: LocalDate(year: 2030, month: 1, day: 1), redemptionPlace: "카페")
/// 기프티콘 키워드가 하나뿐이라 규칙은 기타로 두고, 모델이 기프티콘을 제안하면 근거(키워드 하나)가 있는 줄.
let modelOnlyGifticonText = ["상품권 5,000원", "Valid until 2026.12.31"]
/// 영수증 키워드가 하나뿐이라 규칙은 기타로 두는 줄.
let otherOnlyText = ["영수증 정리"]

extension Fixture {
  /// 저장된 이미지를 식별자로.
  var storedImages: [ImageAsset.ID: IndexedImage] {
    Dictionary(uniqueKeysWithValues: self.store.images.map { ($0.id, $0) })
  }
}
