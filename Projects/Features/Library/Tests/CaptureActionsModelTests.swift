import Core
import CoreGraphics
import Foundation
import ImageAnalysisTesting
import MapTesting
import PasteboardTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 사진 상세의 캡처 정보·바코드 인식. 상세는 닫힐 때까지 이어지므로 결과를 확인한 뒤 Task 를 취소해 끝낸다.
@MainActor
struct CaptureActionsModelTests {
  static let captureLines = ["서울특별시 중구 세종대로 110", "CJ대한통운 1234-5678-9012", "신한은행 110-123-456789"]

  @Test("상세를 열면 저장된 줄에서 주소·송장·계좌번호를 찾는다")
  func findsCaptureInfo() async {
    let photoStore = PhotoStoreClientFake(images: [.capture(id: "c", lines: Self.captureLines)])
    let model = GifticonFixture.captureModel(photoStore: photoStore)

    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.detailID == "c" }
    await waitUntil { model.captureInfo != .loading }

    #expect(model.captureInfo == .loaded(CaptureInfo(
      addresses: [CapturedText(text: "서울특별시 중구 세종대로 110", lineIndex: 0)],
      trackingNumbers: [CapturedText(text: "1234-5678-9012", lineIndex: 1)],
      accountNumbers: [CapturedText(text: "110-123-456789", lineIndex: 2)]
    )))
    // 기프티콘 목록에서 연 상세가 아니다.
    #expect(model.gifticon == nil)
    #expect(model.barcode == .notApplicable)

    await cancelAndWait(detail)
  }

  @Test("읽은 줄이 없거나 행이 없으면 빈 결과다", arguments: [true, false])
  func noLinesGivesEmptyInfo(hasRow: Bool) async {
    let photoStore = PhotoStoreClientFake(images: hasRow ? [.dated(id: "p", nil)] : [])
    let model = GifticonFixture.captureModel(photoStore: photoStore)

    let detail = Task { await model.detailAppeared(id: "p", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }
    #expect(model.captureInfo == .loaded(CaptureInfo(addresses: [], trackingNumbers: [], accountNumbers: [])))

    await cancelAndWait(detail)
  }

  @Test("저장소를 읽지 못하거나 저장소가 없으면 캡처 정보를 쓸 수 없다", arguments: [true, false])
  func storeFailureMakesInfoUnavailable(hasStore: Bool) async {
    let photoStore = hasStore ? PhotoStoreClientFake(error: .failed) : nil
    let model = GifticonFixture.captureModel(photoStore: photoStore)

    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo == .unavailable }

    await cancelAndWait(detail)
  }

  @Test("닫히면 상세 상태를 모두 지운다")
  func closeClearsState() async {
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))])
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = Task { await model.detailAppeared(id: "g", gifticon: Self.item("g")) }
    await waitUntil { model.captureInfo != .loading }
    #expect(model.barcode == .waitingForImage)

    await cancelAndWait(detail)

    #expect(model.detailID == nil)
    #expect(model.gifticon == nil)
    #expect(model.barcode == .notApplicable)
    #expect(model.captureInfo == .loading)
  }

  // MARK: - 바코드

  @Test("다시 그릴 수 있는 바코드는 다시 그린 이미지와 내용으로 크게 보기를 준비한다")
  func detectsRedrawableBarcode() async {
    let barcode = DetectedBarcode(
      payload: "1234567890123",
      symbology: .code128,
      boundingBox: CGRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2)
    )
    let imageAnalysis = ImageAnalysisClientFake(detectBarcodesResult: .success([barcode]))
    let (model, detail) = await Self.openGifticonDetail(imageAnalysis: imageAnalysis)

    await model.detailImageLoaded(.stub(width: 200, height: 200), id: "g")

    guard case let .found(image, payload) = model.barcode else {
      Issue.record("바코드를 찾지 못함: \(model.barcode)")
      return
    }
    #expect(image.isRedrawn)
    #expect(payload == "1234567890123")
    #expect(imageAnalysis.requests == [.detectBarcodes])

    await cancelAndWait(detail)
  }

  @Test("다시 그릴 수 없는 바코드는 원본에서 자른 영역으로 크게 보기를 준비한다")
  func cropsOtherBarcode() async {
    let barcode = DetectedBarcode(
      payload: "8801234567893",
      symbology: .ean13,
      boundingBox: CGRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2)
    )
    let (model, detail) = await Self.openGifticonDetail(
      imageAnalysis: ImageAnalysisClientFake(detectBarcodesResult: .success([barcode]))
    )

    await model.detailImageLoaded(.stub(width: 200, height: 200), id: "g")

    guard case let .found(image, _) = model.barcode else {
      Issue.record("바코드를 찾지 못함: \(model.barcode)")
      return
    }
    #expect(!image.isRedrawn)

    await cancelAndWait(detail)
  }

  @Test("바코드가 없으면 찾지 못했다고 하고, 작은 대체 버전이면 그 사실을 함께 담는다", arguments: [false, true])
  func noBarcodeIsNotFound(isLocalFallback: Bool) async {
    let (model, detail) = await Self.openGifticonDetail(imageAnalysis: ImageAnalysisClientFake())

    await model.detailImageLoaded(.stub(isLocalFallback: isLocalFallback), id: "g")

    #expect(model.barcode == .notFound(isLocalFallback: isLocalFallback))

    await cancelAndWait(detail)
  }

  @Test("인식에 실패하면 실패다")
  func detectionFailureIsFailed() async {
    let (model, detail) = await Self.openGifticonDetail(
      imageAnalysis: ImageAnalysisClientFake(detectBarcodesResult: .failure(.failed))
    )

    await model.detailImageLoaded(.stub(), id: "g")

    #expect(model.barcode == .failed)

    await cancelAndWait(detail)
  }

  @Test("인식 중에 취소되면 이미지 대기로 돌아가 다시 읽으면 다시 찾는다")
  func cancelledDetectionReturnsToWaiting() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let imageAnalysis = ImageAnalysisClientFake(
      classify: { _ in .success([]) },
      recognizeText: { _ in .success([]) },
      detectBarcodes: { _ in
        await gates.pass(counter.next())
        return .success([])
      }
    )
    let (model, detail) = await Self.openGifticonDetail(imageAnalysis: imageAnalysis)

    let detect = Task { await model.detailImageLoaded(.stub(), id: "g") }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.barcode == .detecting)
    await cancelAndWait(detect)
    #expect(model.barcode == .waitingForImage)

    await model.detailImageLoaded(.stub(), id: "g")
    #expect(model.barcode == .notFound(isLocalFallback: false))

    await cancelAndWait(detail)
  }

  @Test("인식 중에 닫고 다른 사진을 열면 지난 인식 결과는 새 상세를 바꾸지 않는다")
  func lateDetectionAfterReopenIsDropped() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let barcode = DetectedBarcode(
      payload: "1",
      symbology: .qrCode,
      boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)
    )
    let imageAnalysis = ImageAnalysisClientFake(
      classify: { _ in .success([]) },
      recognizeText: { _ in .success([]) },
      detectBarcodes: { _ in
        await gates.pass(0)
        return .success([barcode])
      }
    )
    let (model, first) = await Self.openGifticonDetail(imageAnalysis: imageAnalysis)
    let detect = Task { await model.detailImageLoaded(.stub(), id: "g") }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let second = Task { await model.detailAppeared(id: "h", gifticon: Self.item("h")) }
    await waitUntil { model.detailID == "h" }
    gates.open(0)
    await detect.value

    #expect(model.detailID == "h")
    #expect(model.barcode == .waitingForImage)

    await cancelAndWait(second)
  }

  @Test("기프티콘 목록에서 연 상세가 아니면 바코드를 찾지 않는다")
  func nonGifticonDetailSkipsDetection() async {
    let imageAnalysis = ImageAnalysisClientFake()
    let model = GifticonFixture.captureModel(
      photoStore: PhotoStoreClientFake(images: [.capture(id: "c", lines: [])]),
      imageAnalysis: imageAnalysis
    )
    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }

    await model.detailImageLoaded(.stub(), id: "c")
    model.detailImageUnavailable(id: "c")

    #expect(model.barcode == .notApplicable)
    #expect(imageAnalysis.requests.isEmpty)

    await cancelAndWait(detail)
  }

  @Test("상세 이미지를 볼 수 없으면 바코드를 찾을 수 없다고 한다")
  func unavailableImage() async {
    let (model, detail) = await Self.openGifticonDetail(imageAnalysis: ImageAnalysisClientFake())

    // 다른 사진의 신호는 무시한다.
    model.detailImageUnavailable(id: "other")
    #expect(model.barcode == .waitingForImage)

    model.detailImageUnavailable(id: "g")
    #expect(model.barcode == .imageUnavailable)

    await cancelAndWait(detail)
  }

  // MARK: - Helpers

  static func item(
    _ id: String,
    expiryDate: LocalDate? = .date(2026, 11, 1),
    isUsed: Bool = false
  ) -> GifticonListItem {
    GifticonListItem(
      asset: .stub(id: id),
      status: .extracted(GifticonInfo(expiryDate: expiryDate, redemptionPlace: "카페")),
      isUsed: isUsed
    )
  }

  /// 기프티콘 "g" 의 상세를 연다. 캡처 정보를 읽을 때까지 기다린다.
  static func openGifticonDetail(
    imageAnalysis: ImageAnalysisClientFake
  ) async -> (CaptureActionsModel, Task<Void, Never>) {
    let photoStore = PhotoStoreClientFake(images: [
      .gifticon(id: "g", expiryDate: .date(2026, 11, 1)),
      .gifticon(id: "h", expiryDate: .date(2026, 11, 2)),
    ])
    let model = GifticonFixture.captureModel(photoStore: photoStore, imageAnalysis: imageAnalysis)
    let detail = Task { await model.detailAppeared(id: "g", gifticon: Self.item("g")) }
    await waitUntil { model.captureInfo != .loading }
    #expect(model.barcode == .waitingForImage)
    return (model, detail)
  }
}
