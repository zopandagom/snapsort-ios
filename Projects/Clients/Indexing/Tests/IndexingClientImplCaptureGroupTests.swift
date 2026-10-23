import ClassifierTesting
import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import IndexingImpl

/// 캡처 묶음 추출: 2단계에서 함께 저장하고, 추출하지 않은 저장 행은 OCR 없이 저장된 줄로 소급 추출한다.
/// 소급은 진행률·`isFinished` 에 넣지 않으므로 변경 스트림을 끝낸 뒤 `run()` 스트림이 끝날 때까지 읽는다.
/// OCR 줄은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplCaptureGroupTests {
  @Test("2단계에서 쇼핑·대화·지도로 분류되면 읽은 줄로 묶음 값을 함께 저장하고, 셋이 아니면 값이 없다")
  func extractsCaptureGroupsInTextPass() async {
    let fixture = Fixture(
      library: [
        .stub(id: "shopping", creationDate: date(month: 10, day: 4), isScreenshot: true),
        .stub(id: "chat", creationDate: date(month: 10, day: 3), isScreenshot: true),
        .stub(id: "map", creationDate: date(month: 10, day: 2), isScreenshot: true),
        .stub(id: "receipt", creationDate: date(month: 10, day: 1), isScreenshot: true),
      ],
      text: ["shopping": shoppingText, "chat": chatText, "map": mapText, "receipt": receiptText]
    )

    await fixture.runToEnd()

    let images = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(images["shopping"]?.categories == [.shopping])
    #expect(images["shopping"]?.captureGroups == extractedShopping)
    #expect(images["chat"]?.categories == [.chat])
    #expect(images["chat"]?.captureGroups == extractedChat)
    #expect(images["map"]?.categories == [.map])
    #expect(images["map"]?.captureGroups == extractedMap)
    #expect(images["receipt"]?.categories == [.receipt])
    #expect(images["receipt"]?.captureGroups == nil)
    // 2단계의 저장에 함께 들어가므로 소급 저장은 없다.
    #expect(fixture.store.savedCaptureGroupBatches.isEmpty)
  }

  @Test("2단계: 영수증이면서 쇼핑이면 두 추출 값을 같은 저장에 넣는다")
  func storesReceiptAndGroupsInOneSave() async {
    let both = shoppingText + receiptText
    let fixture = Fixture(
      library: [.stub(id: "both", creationDate: date(month: 10, day: 1), isScreenshot: true)],
      text: ["both": both]
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.categories == [.receipt, .shopping])
    #expect(image?.receipt == ReceiptExtractor.extract(from: ocrLines(both)))
    #expect(image?.receipt?.amount == extractedReceipt.amount)
    #expect(image?.captureGroups == extractedShopping)
    #expect(fixture.store.savedBatches.contains { $0.contains { $0.id == "both" && $0.captureGroups != nil } })
    #expect(fixture.store.savedReceiptBatches.isEmpty)
    #expect(fixture.store.savedCaptureGroupBatches.isEmpty)
  }

  @Test("모델이 더한 지도 카테고리도 같은 저장에서 지역을 추출한다")
  func extractsForModelAddedCategory() async {
    // 지도 키워드가 하나뿐이라 규칙은 기타이고, 모델이 제안한 지도는 키워드 하나로 근거를 받는다.
    let lines = ["지도", "서울 강남구"]
    let classifier = ClassifierClientFake(classifyResult: .success([.map]))
    let fixture = Fixture(
      library: [.stub(id: "map", creationDate: date(month: 10, day: 1), isScreenshot: true)],
      text: ["map": lines],
      classifier: classifier
    )

    await fixture.runToEnd()

    #expect(fixture.store.images.only?.categories == [.map])
    #expect(fixture.store.images.only?.captureGroups == extractedMap)
  }

  @Test("추출하지 않은 저장 행은 OCR 없이 저장된 줄로 소급 추출하고, 대상이 비면 같은 값의 진행률을 한 번 더 보낸다")
  func backfillsStoredRowsWithoutRecognizing() async {
    let asset = ImageAsset.stub(id: "shopping", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(library: [asset], stored: [recognizedShopping(asset)])
    let extractedFixture = Fixture(library: [asset], stored: [recognizedShopping(asset, groups: extractedShopping)])

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await extractedFixture.allProgress()

    #expect(fixture.store.savedCaptureGroupBatches == [["shopping": extractedShopping]])
    #expect(fixture.store.images.only?.captureGroups == extractedShopping)
    #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    #expect(fixture.analysis.requests.isEmpty)
    #expect(extractedFixture.store.savedCaptureGroupBatches.isEmpty)
    #expect(Array(progresses.dropLast()) == progressesWithoutTargets)
    #expect(progresses.last == progressesWithoutTargets.last)
    #expect(progresses.last?.isFinished == true)
  }

  @Test("소급은 행 카테고리의 필드만 추출해 저장한다")
  func backfillRestrictsToRowCategories() async {
    let asset = ImageAsset.stub(id: "chat", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let row = IndexedImage(
      asset: asset,
      labels: defaultLabels,
      textRecognition: .recognized(ocrLines(shoppingText + chatText + mapText)),
      categories: [.chat]
    )
    let fixture = Fixture(library: [asset], stored: [row])

    await fixture.runToEnd()

    #expect(fixture.store.images.only?.captureGroups == extractedChat)
  }

  @Test("캡처 묶음 소급은 기프티콘·영수증 소급 뒤·2단계 앞에서 최신순 batchSize 장씩 저장한다")
  func backfillsAfterGifticonsAndReceiptsBeforeTextPass() async {
    let log = Mutex<[String]>([])
    let shops = (1 ... 3).map {
      ImageAsset.stub(id: "s\($0)", creationDate: date(month: 5, day: $0), isScreenshot: true)
    }
    let receipt = ImageAsset.stub(id: "r", creationDate: date(month: 4, day: 2), isScreenshot: true)
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 4, day: 1), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: shops + [receipt, coupon, ocrPending],
      stored: shops.map { recognizedShopping($0) } + [
        recognizedReceipt(receipt),
        recognizedGifticon(coupon, text: gifticonText),
        pending(ocrPending),
      ],
      text: ["p": shoppingText],
      onRecognize: { id in log.withLock { $0.append("ocr \(id)") } },
      onSaveGifticons: { gifticons in log.withLock { $0.append("gifticon \(gifticons.keys.sorted())") } },
      receipt: ReceiptStoreOptions(onSave: { batch in log.withLock { $0.append("receipt \(batch.keys.sorted())") } }),
      captureGroup: CaptureGroupStoreOptions(onSave: { batch in
        log.withLock { $0.append("captureGroup \(batch.keys.sorted())") }
      }),
      batchSize: 2
    )

    await fixture.runToEnd()

    #expect(log.withLock { $0 } == [
      "gifticon [\"coupon\"]", "receipt [\"r\"]", "captureGroup [\"s2\", \"s3\"]", "captureGroup [\"s1\"]", "ocr p",
    ])
    #expect(fixture.storedCaptureGroups == [
      "s1": extractedShopping, "s2": extractedShopping, "s3": extractedShopping, "p": extractedShopping,
    ])
  }

  @Test("캡처 묶음 소급 배치 사이에 온 삭제 변경을 먼저 반영하고 지워진 이미지는 저장하지 않는다")
  func appliesRemovalBetweenBackfillBatches() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let assets = ["a", "b", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedShopping($0) },
      captureGroup: CaptureGroupStoreOptions(onSave: { groups in
        if Set(groups.keys) == ["a"] {
          library.current?.sendIncrementalChange(removed: ["b"])
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번. 그 뒤에 저장을 끝내 다음 배치 경계에서 반영되게 한다.
          await changeRequests.wait(until: 2)
          library.current?.finishImageChanges()
        }
      }),
      batchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    for await _ in fixture.indexing.run() {}

    #expect(fixture.store.savedCaptureGroupBatches.map { Set($0.keys) } == [["a"], ["c"]])
    #expect(fixture.store.deletedBatches == [["b"]])
    #expect(fixture.storedCaptureGroups == ["a": extractedShopping, "c": extractedShopping])
  }
}

// 캡처 묶음 테스트(IndexingClientImplCaptureGroupTests·IndexingClientImplCaptureGroupFailureTests) 공통 준비.
// 몰·브랜드·지역 이름과 OCR 줄은 지어낸 텍스트다.

/// 쇼핑 키워드 두 개("장바구니"·"구매하기")로 쇼핑이 되고 쿠팡·나이키를 찾는 줄.
let shoppingText = ["장바구니", "구매하기", "쿠팡", "나이키 에어맥스"]
/// 대화 키워드("문자메시지")로 대화가 되고 메시지 앱 문구를 찾는 줄.
let chatText = ["문자 메시지", "오후 3:12"]
/// 지도 키워드 두 개("길찾기"·"대중교통")로 지도가 되고 서울 강남구를 찾는 줄.
let mapText = ["길찾기", "대중교통", "서울 강남구"]

let extractedShopping = CaptureGroups(mall: ShoppingMall(id: "coupang"), brand: ShoppingBrand(id: "nike"))
let extractedChat = CaptureGroups(chatApp: .messages)
let extractedMap = CaptureGroups(regions: [KoreanRegion(id: "seoul:강남구")!])

/// 저장소 Fake 의 캡처 묶음 소급 호출 실패·한도·훅. `Fixture(captureGroup:)` 로 넘긴다.
struct CaptureGroupStoreOptions {
  var error: PhotoStoreError?
  var saveLimit: Int?
  var onSave: @Sendable ([ImageAsset.ID: CaptureGroups]) async -> Void = { _ in }
}

/// 2단계를 마친 쇼핑 저장 결과. `groups` 가 nil 이면 추출하지 않은 행(캡처 묶음 소급 대상)이다.
func recognizedShopping(
  _ asset: ImageAsset,
  text: [String] = shoppingText,
  groups: CaptureGroups? = nil
) -> IndexedImage {
  IndexedImage(
    asset: asset,
    labels: defaultLabels,
    textRecognition: .recognized(ocrLines(text)),
    categories: [.shopping],
    captureGroups: groups
  )
}

extension Fixture {
  /// 저장소에서 캡처 묶음 값이 있는 이미지만.
  var storedCaptureGroups: [ImageAsset.ID: CaptureGroups] {
    self.store.images.reduce(into: [:]) { result, image in
      result[image.id] = image.captureGroups
    }
  }
}
