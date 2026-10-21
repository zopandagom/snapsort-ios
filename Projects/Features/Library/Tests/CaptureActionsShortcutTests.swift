import Core
import Foundation
import MapTesting
import PasteboardTesting
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 상세의 지도·복사와 날짜 변경.
@MainActor
struct CaptureActionsShortcutTests {
  // MARK: - 지도·복사

  @Test("주소를 누르면 원문 그대로 지도 앱으로 넘긴다")
  func addressOpensMaps() async {
    let map = MapClientFake()
    let model = GifticonFixture.captureModel(photoStore: PhotoStoreClientFake(), map: map)
    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }

    await model.addressTapped(CapturedText(text: "서울특별시 중구 세종대로 110", lineIndex: 0))

    #expect(map.openedAddresses == ["서울특별시 중구 세종대로 110"])
    #expect(model.alert == nil)

    await cancelAndWait(detail)
  }

  @Test("지도 앱을 열지 못하면 알린다")
  func mapsUnavailableAlerts() async {
    let model = GifticonFixture.captureModel(photoStore: PhotoStoreClientFake(), map: MapClientFake(openResult: false))
    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }

    await model.addressTapped(CapturedText(text: "서울특별시 중구 세종대로 110", lineIndex: 0))

    #expect(model.alert == .mapsUnavailable)

    await cancelAndWait(detail)
  }

  @Test("지도 앱 열기가 끝나기 전에 상세를 닫고 다시 열면 늦은 실패를 새 상세에 알리지 않는다", arguments: ["c", "d"])
  func lateMapsFailureAfterReopenIsDropped(reopenedID: String) async {
    let gates = CallGates(holding: [0])
    let map = MapClientFake(openResult: false) { await gates.pass(0) }
    let model = GifticonFixture.captureModel(photoStore: PhotoStoreClientFake(), map: map)
    let first = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }
    let tap = Task { await model.addressTapped(CapturedText(text: "서울특별시 중구 세종대로 110", lineIndex: 0)) }
    await waitUntil { gates.hasEntered(0) }

    await cancelAndWait(first)
    let second = Task { await model.detailAppeared(id: reopenedID, gifticon: nil) }
    await waitUntil { model.detailID == reopenedID && model.captureInfo != .loading }
    gates.open(0)
    await tap.value

    #expect(map.openedAddresses == ["서울특별시 중구 세종대로 110"])
    #expect(model.alert == nil)

    await cancelAndWait(second)
  }

  @Test("복사가 끝나기 전에 상세를 닫고 다시 열면 복사는 하고 새 상세에 복사 안내를 띄우지 않는다", arguments: ["c", "d"])
  func lateCopyAfterReopenIsDropped(reopenedID: String) async {
    let gates = CallGates(holding: [0])
    let pasteboard = PasteboardClientFake { await gates.pass(0) }
    let model = GifticonFixture.captureModel(photoStore: PhotoStoreClientFake(), pasteboard: pasteboard)
    let first = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }
    let tap = Task { await model.numberCopyTapped(CapturedText(text: "1234-5678-9012", lineIndex: 1)) }
    await waitUntil { gates.hasEntered(0) }

    await cancelAndWait(first)
    let second = Task { await model.detailAppeared(id: reopenedID, gifticon: nil) }
    await waitUntil { model.detailID == reopenedID && model.captureInfo != .loading }
    gates.open(0)
    await tap.value

    #expect(pasteboard.copiedTexts == ["1234-5678-9012"])
    #expect(model.copied == nil)

    await cancelAndWait(second)
  }

  @Test("번호를 누르면 원문 그대로 복사하고, 누를 때마다 복사 안내가 바뀐다")
  func numberCopy() async {
    let pasteboard = PasteboardClientFake()
    let model = GifticonFixture.captureModel(photoStore: PhotoStoreClientFake(), pasteboard: pasteboard)
    let detail = Task { await model.detailAppeared(id: "c", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }
    let number = CapturedText(text: "1234-5678-9012", lineIndex: 1)

    await model.numberCopyTapped(number)
    let first = model.copied
    await model.numberCopyTapped(number)

    #expect(pasteboard.copiedTexts == ["1234-5678-9012", "1234-5678-9012"])
    #expect(first?.number == number)
    #expect(model.copied?.number == number)
    #expect(model.copied != first)

    await cancelAndWait(detail)
  }

  // MARK: - 날짜

  @Test("상세를 연 채 날짜가 바뀌면 오늘이 바뀌어 같은 만료일의 D-n 이 바뀐다")
  func dayChangeUpdatesToday() async {
    let clock = TestClock(now: .seoul(2026, 10, 19, hour: 23, minute: 59), calendar: .seoul)
    let photoStore = CaptureActionsUsageTests.photoStore()
    let model = GifticonFixture.captureModel(photoStore: photoStore, clock: clock)
    let detail = await CaptureActionsUsageTests.open(model, photoStore: photoStore)
    #expect(GifticonDue(expiryDate: .date(2026, 10, 19), today: model.today) == .remaining(days: 0))

    clock.now = .seoul(2026, 10, 20, hour: 0, minute: 1)
    model.dayChanged()
    #expect(model.today == .date(2026, 10, 20))
    #expect(GifticonDue(expiryDate: .date(2026, 10, 19), today: model.today) == .expired(daysAgo: 1))

    // 시간대가 바뀌어도 다시 계산한다(서울 10-20 00:01 은 로스앤젤레스 10-19 08:01).
    clock.calendar = .losAngeles
    model.dayChanged()
    #expect(model.today == .date(2026, 10, 19))
    #expect(model.calendar.timeZone.identifier == "America/Los_Angeles")

    await cancelAndWait(detail)
  }
}
