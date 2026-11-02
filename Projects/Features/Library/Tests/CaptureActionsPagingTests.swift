import Core
import CoreGraphics
import Foundation
import ImageAnalysisTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 사진 상세에서 장을 넘길 때의 캡처 행동. View 는 지금 장이 바뀌면 지난 장의 `.task(id:)` 를 취소하고 새 장으로
/// `detailAppeared(id:gifticon:)` 를 다시 부른다. 취소와 새 시작의 순서는 정해지지 않아 두 순서를 모두 본다.
@MainActor
struct CaptureActionsPagingTests {
  @Test("기프티콘 장을 열면 저장소에서 기프티콘을 한 번 다시 읽어 경로의 옛 값을 고친다")
  func gifticonPageReloadsOnAppear() async {
    // 경로 항목은 연 때 값(미사용)이고, 그 뒤 이 상세에서 사용함으로 바꿨다.
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))], usedIDs: ["g"])
    let model = GifticonFixture.captureModel(photoStore: photoStore)

    let detail = Task { await model.detailAppeared(id: "g", gifticon: CaptureActionsModelTests.item("g")) }
    await waitUntil { model.gifticon?.isUsed == true }
    #expect(model.barcode == .waitingForImage)

    await cancelAndWait(detail)
  }

  @Test("다시 읽기에 실패하면 경로의 값을 둔다")
  func failedReloadKeepsRouteValue() async {
    let photoStore = PhotoStoreClientFake(error: .failed)
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let item = CaptureActionsModelTests.item("g", isUsed: true)

    let detail = Task { await model.detailAppeared(id: "g", gifticon: item) }
    await waitUntil { model.captureInfo == .unavailable }
    await settle()
    #expect(model.gifticon == item)

    await cancelAndWait(detail)
  }

  @Test("기프티콘 없는 장은 열 때 기프티콘을 다시 읽지 않는다")
  func nonGifticonPageSkipsReload() async {
    let gates = CallGates(holding: [])
    let photoStore = PhotoStoreClientFake(
      images: [.capture(id: "c", lines: CaptureActionsModelTests.captureLines)],
      onGifticon: { await gates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)

    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }
    await settle()
    #expect(!gates.hasEntered(0))

    await cancelAndWait(detail)
  }

  @Test("장을 넘기면 지난 장의 바코드 인식 결과와 정리가 새 장을 바꾸지 않는다", arguments: [true, false])
  func previousPageResultsAreDropped(newStartsFirst: Bool) async {
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
    let (model, first) = await CaptureActionsModelTests.openGifticonDetail(imageAnalysis: imageAnalysis)
    let detect = Task { await model.detailImageLoaded(.stub(), id: "g") }
    await waitUntil { gates.hasEntered(0) }

    let second: Task<Void, Never>
    if newStartsFirst {
      second = Task { await model.detailAppeared(id: "h", gifticon: CaptureActionsModelTests.item("h")) }
      await waitUntil { model.detailID == "h" }
      await cancelAndWait(first)
    } else {
      await cancelAndWait(first)
      second = Task { await model.detailAppeared(id: "h", gifticon: CaptureActionsModelTests.item("h")) }
      await waitUntil { model.detailID == "h" }
    }
    await waitUntil { model.captureInfo != .loading }
    gates.open(0)
    await detect.value
    await settle()

    // 지난 장의 정리는 새 장의 상태를 지우지 않는다.
    #expect(model.detailID == "h")
    #expect(model.detailRequest != nil)
    #expect(model.gifticon?.id == "h")
    #expect(model.barcode == .waitingForImage)

    await cancelAndWait(second)
  }

  @Test("사용 여부를 쓰는 중에 넘기면 쓰기는 끝나 쓰기 번호가 오르고, 새 장의 기프티콘은 바뀌지 않는다")
  func writeFinishesAfterPaging() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [
        .gifticon(id: "g", expiryDate: .date(2026, 11, 1)),
        .gifticon(id: "h", expiryDate: .date(2026, 11, 2)),
      ],
      onSetGifticonUsed: { await gates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let first = await CaptureActionsUsageTests.open(model, photoStore: photoStore)
    let write = Task { await model.usedButtonTapped() }
    await waitUntil { gates.hasEntered(0) }

    // 새 장이 먼저 시작하고 지난 장이 뒤에 취소된다.
    let second = Task { await model.detailAppeared(id: "h", gifticon: CaptureActionsModelTests.item("h")) }
    await waitUntil { model.detailID == "h" && model.captureInfo != .loading }
    await cancelAndWait(first)
    gates.open(0)
    await write.value
    await settle()

    #expect(model.usageRevision == 1)
    #expect(photoStore.usedIDs == ["g"])
    #expect(model.gifticon?.id == "h")
    #expect(model.gifticon?.isUsed == false)
    #expect(!model.isUpdatingUsage)

    await cancelAndWait(second)
  }
}
