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

/// 영수증 추출: 2단계에서 함께 저장하고, 추출하지 않은 저장 행은 OCR 없이 저장된 줄로 소급 추출한다.
/// 소급은 진행률·`isFinished` 에 넣지 않으므로 변경 스트림을 끝낸 뒤 `run()` 스트림이 끝날 때까지 읽는다.
/// OCR 줄·가게 이름은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplReceiptTests {
  @Test("2단계에서 영수증으로 분류되면 읽은 줄로 가게·금액을 추출해 함께 저장한다")
  func extractsReceiptInTextPass() async {
    let fixture = Fixture(
      library: [.stub(id: "receipt", creationDate: date(month: 10, day: 1), isScreenshot: true)],
      text: ["receipt": receiptText]
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.categories == [.receipt])
    #expect(image?.receipt == extractedReceipt)
    #expect(fixture.store.savedReceiptBatches.isEmpty)
  }

  @Test("2단계: 기프티콘이면서 영수증이면 두 추출 값을 같은 저장에 넣고, 영수증이 아니면 영수증 값이 없다")
  func storesBothValuesInOneSave() async {
    let both = gifticonText + receiptText
    let fixture = Fixture(
      library: [
        .stub(id: "both", creationDate: date(month: 10, day: 2), isScreenshot: true),
        .stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true),
      ],
      text: ["both": both, "coupon": gifticonText]
    )

    await fixture.runToEnd()

    let images = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(images["both"]?.categories == [.gifticon, .receipt])
    #expect(images["both"]?.gifticon == extractedGifticon)
    #expect(images["both"]?.receipt == ReceiptExtractor.extract(from: ocrLines(both)))
    #expect(images["both"]?.receipt?.amount == extractedReceipt.amount)
    #expect(images["coupon"]?.receipt == nil)
    // 두 값은 2단계의 한 저장에 들어가고 소급 저장은 없다.
    #expect(fixture.store.savedBatches.contains { $0.contains { $0.id == "both" && $0.receipt != nil } })
    #expect(fixture.store.savedReceiptBatches.isEmpty)
    #expect(fixture.store.savedGifticonBatches.isEmpty)
  }

  @Test("추출하지 않은 영수증 저장 행은 OCR 없이 저장된 줄로 소급 추출하고, 대상이 비면 같은 값의 진행률을 한 번 더 보낸다")
  func backfillsStoredReceiptWithoutRecognizing() async {
    let asset = ImageAsset.stub(id: "receipt", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(library: [asset], stored: [recognizedReceipt(asset)])
    let extractedFixture = Fixture(library: [asset], stored: [recognizedReceipt(asset, receipt: extractedReceipt)])

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await extractedFixture.allProgress()

    #expect(fixture.store.savedReceiptBatches == [["receipt": extractedReceipt]])
    #expect(fixture.store.images.only?.receipt == extractedReceipt)
    #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    #expect(fixture.analysis.requests.isEmpty)
    #expect(extractedFixture.store.savedReceiptBatches.isEmpty)
    #expect(Array(progresses.dropLast()) == progressesWithoutTargets)
    #expect(progresses.last == progressesWithoutTargets.last)
    #expect(progresses.last?.isFinished == true)
  }

  @Test("영수증 소급은 기프티콘 소급 뒤·2단계 앞에서 최신순 batchSize 장씩 저장한다")
  func backfillsAfterGifticonsBeforeTextPass() async {
    let log = Mutex<[String]>([])
    let receipts = (1 ... 3).map {
      ImageAsset.stub(id: "r\($0)", creationDate: date(month: 5, day: $0), isScreenshot: true)
    }
    let coupon = ImageAsset.stub(id: "coupon", creationDate: date(month: 4, day: 1), isScreenshot: true)
    let ocrPending = ImageAsset.stub(id: "p", creationDate: date(month: 6, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: receipts + [coupon, ocrPending],
      stored: receipts.map { recognizedReceipt($0) } + [
        recognizedGifticon(coupon, text: gifticonText),
        pending(ocrPending),
      ],
      text: ["p": receiptText],
      onRecognize: { id in log.withLock { $0.append("ocr \(id)") } },
      onSaveGifticons: { gifticons in log.withLock { $0.append("gifticon \(gifticons.keys.sorted())") } },
      receipt: ReceiptStoreOptions(onSave: { batch in log.withLock { $0.append("receipt \(batch.keys.sorted())") } }),
      batchSize: 2
    )

    await fixture.runToEnd()

    #expect(log.withLock { $0 } == [
      "gifticon [\"coupon\"]", "receipt [\"r2\", \"r3\"]", "receipt [\"r1\"]", "ocr p",
    ])
    #expect(fixture.storedReceipts == [
      "r1": extractedReceipt,
      "r2": extractedReceipt,
      "r3": extractedReceipt,
      "p": extractedReceipt,
    ])
  }

  @Test("영수증 소급 배치 사이에 온 삭제 변경을 먼저 반영하고 지워진 이미지는 저장하지 않는다")
  func appliesRemovalBetweenBackfillBatches() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let assets = ["a", "b", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedReceipt($0) },
      receipt: ReceiptStoreOptions(onSave: { receipts in
        if Set(receipts.keys) == ["a"] {
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

    #expect(fixture.store.savedReceiptBatches.map { Set($0.keys) } == [["a"], ["c"]])
    #expect(fixture.store.deletedBatches == [["b"]])
    #expect(fixture.storedReceipts == ["a": extractedReceipt, "c": extractedReceipt])
  }
}

// 영수증 테스트(IndexingClientImplReceiptTests·IndexingClientImplReceiptFailureTests) 공통 준비.

/// `receiptText`(["영수증", "합계 12,000원"])에서 추출한 값. 위쪽 줄은 머리글뿐이라 가게 모름이다.
let extractedReceipt = ReceiptInfo(
  storeName: nil,
  amount: ReceiptAmount(minorUnits: 12000, currency: .krw),
  isCancelled: false
)

/// 저장소 Fake 의 영수증 소급 호출 실패·한도·훅. `Fixture(receipt:)` 로 넘긴다.
struct ReceiptStoreOptions {
  var error: PhotoStoreError?
  var saveLimit: Int?
  var onSave: @Sendable ([ImageAsset.ID: ReceiptInfo]) async -> Void = { _ in }
}

/// 2단계를 마친 영수증 저장 결과. `receipt` 가 nil 이면 추출하지 않은 행(영수증 소급 대상)이다.
func recognizedReceipt(_ asset: ImageAsset, text: [String] = receiptText, receipt: ReceiptInfo? = nil) -> IndexedImage {
  IndexedImage(
    asset: asset,
    labels: defaultLabels,
    textRecognition: .recognized(ocrLines(text)),
    categories: [.receipt],
    receipt: receipt
  )
}

extension Fixture {
  /// 저장소에서 영수증 추출 값이 있는 이미지만.
  var storedReceipts: [ImageAsset.ID: ReceiptInfo] {
    self.store.images.reduce(into: [:]) { result, image in
      result[image.id] = image.receipt
    }
  }
}
