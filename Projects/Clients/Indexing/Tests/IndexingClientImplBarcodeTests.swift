import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryTesting
import Testing
@testable import IndexingImpl

/// 1단계 바코드 확인: 위치 없고 라벨로는 OCR 대상이 아닌 이미지는 같은 썸네일로 바코드를 보고, 있으면 OCR 대기로 저장한다.
/// 실패는 바코드 없음으로 보고, 취소면 그 배치를 저장하지 않는다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplBarcodeTests {
  @Test("바코드가 있으면 OCR 대기로 저장하고 벡터를 만들지 않으며 2단계에서 글자를 읽는다")
  func barcodeMakesPending() async {
    let coupon = cameraPhoto("coupon", day: 9)
    let fixture = Fixture(
      library: [coupon],
      labels: ["coupon": photoLabels],
      text: ["coupon": ["교환처 카페", "유효기간 2026.12.31"]],
      featurePrint: .available,
      barcode: BarcodeOptions(found: ["coupon"])
    )

    await fixture.runToEnd()

    let saved = fixture.store.savedBatches.first?.only
    #expect(saved?.textRecognition == .pending)
    #expect(saved?.categories == IndexingRun.pendingCategories(asset: coupon, labels: photoLabels))
    #expect(saved?.categories.contains(.other) == false)
    #expect(saved?.featurePrint == nil)
    #expect(fixture.featurePrintRequestCount == 0)
    #expect(fixture.analysis.requests.contains(.recognizeText))
    #expect(fixture.store.images.only?.textRecognition == .recognized(ocrLines(["교환처 카페", "유효기간 2026.12.31"])))
    #expect(fixture.store.images.only?.categories.contains(.gifticon) == true)
  }

  @Test("바코드가 없으면 지금처럼 OCR 하지 않고 벡터 대상이면 벡터를 만든다")
  func noBarcodeKeepsNotNeeded() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(library: [photo], labels: ["photo": photoLabels], featurePrint: .available)

    await fixture.runToEnd()

    #expect(fixture.store.images.only?.textRecognition == .notNeeded)
    #expect(fixture.barcodeRequestCount == 1)
    #expect(fixture.featurePrintRequestCount == 1)
    #expect(!fixture.analysis.requests.contains(.recognizeText))
  }

  @Test("바코드 인식에 실패하면 바코드 없음으로 보고 분류를 저장하며 미룬 수에 세지 않는다")
  func failureCountsAsNoBarcode() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      barcode: BarcodeOptions(failures: ["photo"])
    )

    let finished = await fixture.runToEnd()

    #expect(fixture.store.images.only?.textRecognition == .notNeeded)
    #expect(fixture.barcodeRequestCount == 1)
    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
  }

  @Test("위치 있는 사진은 바코드를 확인하지 않는다")
  func skipsPhotoWithLocation() async {
    let photo = ImageAsset.stub(id: "photo", creationDate: date(month: 5, day: 9), coordinate: seoul)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      barcode: BarcodeOptions(found: ["photo"])
    )

    await fixture.runToEnd()

    #expect(fixture.barcodeRequestCount == 0)
    #expect(fixture.store.images.only?.textRecognition == .notNeeded)
  }

  @Test("라벨·메타데이터로 이미 OCR 대상이면 바코드를 확인하지 않는다")
  func skipsTextRecognitionTargets() async {
    let labeled = ImageAsset.stub(id: "labeled", creationDate: date(month: 5, day: 9))
    let screenshot = ImageAsset.stub(id: "shot", creationDate: date(month: 5, day: 8), isScreenshot: true)
    let fixture = Fixture(
      library: [labeled, screenshot],
      labels: ["shot": photoLabels],
      barcode: BarcodeOptions(found: ["labeled", "shot"])
    )

    await fixture.runToEnd()

    #expect(fixture.barcodeRequestCount == 0)
    #expect(fixture.analysis.requests.count { $0 == .recognizeText } == 2)
  }

  @Test("분류 뒤 같은 썸네일로 바코드를 확인하고 그 뒤 벡터를 만들며 1단계에서 원본을 읽지 않는다")
  func checksAfterClassifyWithThumbnail() async {
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(library: [photo], labels: ["photo": photoLabels], featurePrint: .available)

    await fixture.runToEnd()

    #expect(fixture.analysis.requests == [
      .classify(minimumConfidence: ClassificationRules.minimumLabelConfidence),
      .detectBarcodes,
      .featurePrint,
    ])
    #expect(fixture.thumbnailLoadIDs == ["photo"])
    #expect(fixture.photoLibrary.largestLoadIDs.isEmpty)
  }

  @Test("바코드 인식 도중 취소되면 그 배치를 저장하지 않는다")
  func cancellationDuringBarcodeCheck() async {
    let gate = Gate()
    let started = CallCount()
    let photo = cameraPhoto("photo", day: 9)
    let fixture = Fixture(
      library: [photo],
      labels: ["photo": photoLabels],
      barcode: BarcodeOptions(found: ["photo"], onDetect: { _ in
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

  @Test("바코드로 넘어간 이미지는 1단계 끝 진행률의 OCR 대기 수에 든다")
  func barcodeImageCountsAsPendingText() async {
    let coupon = cameraPhoto("coupon", day: 9)
    let photo = cameraPhoto("photo", day: 8)
    let fixture = Fixture(
      library: [coupon, photo],
      labels: ["coupon": photoLabels, "photo": photoLabels],
      barcode: BarcodeOptions(found: ["coupon"])
    )

    let progresses = await fixture.allProgress()

    let classified = progresses.first { $0.indexedCount == 2 }
    #expect(classified?.pendingTextCount == 1)
    #expect(classified?.recognizedTextCount == 0)
    #expect(progresses.last?.recognizedTextCount == 1)
  }
}
