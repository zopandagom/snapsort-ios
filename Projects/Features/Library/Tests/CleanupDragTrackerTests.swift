import CoreGraphics
import Foundation
import Testing
@testable import LibraryFeature

/// 정리 화면 체크 원 열 오버레이의 누름·끌기 추적(`CleanupDragTracker`): 탭은 하나 토글, 끌기 거리를 넘으면 범위 끌기,
/// 취소는 토글하지 않음, Model 이 끌기를 먼저 끝내면 뒤따른 이동을 무시 (docs/ARCHITECTURE.md §4 정리 도우미 선택).
/// 기본 데이터(`CleanupFixture`)의 화면 순서는 `expired`·`estimated`(만료됨) → `used`(사용함), 기본 선택은 `expired`·`used` 다.
/// 줄은 y 100~170·180~250·260~330, 체크 원은 그 줄의 x 0~44, 목록은 y 0~1000 이라 손가락이 끝 영역에 닿지 않는다.
@MainActor
struct CleanupDragTrackerTests {
  static let rows: [String: ClosedRange<CGFloat>] = [
    "expired": 100 ... 170,
    "estimated": 180 ... 250,
    "used": 260 ... 330,
  ]

  static func tracker() -> CleanupDragTracker {
    let tracker = CleanupDragTracker()
    tracker.order = ["expired", "estimated", "used"]
    tracker.listFrame = CGRect(x: 0, y: 0, width: 400, height: 1000)
    for (id, range) in Self.rows {
      tracker.rowFrames[id] = CGRect(x: 0, y: range.lowerBound, width: 400, height: range.upperBound - range.lowerBound)
    }
    return tracker
  }

  static var circles: [String: CGRect] {
    rows.mapValues { CGRect(x: 0, y: $0.lowerBound, width: 44, height: $0.upperBound - $0.lowerBound) }
  }

  /// 줄 가운데 높이.
  static func midY(_ id: String) -> CGFloat {
    let range = Self.rows[id]!
    return (range.lowerBound + range.upperBound) / 2
  }

  static func touch(
    _ tracker: CleanupDragTracker,
    start: CGPoint,
    to location: CGPoint,
    model: CleanupModel
  ) {
    tracker.touchChanged(start: start, location: location, circles: self.circles, model: model)
  }

  @Test("체크 원을 누르고 끌기 거리보다 덜 움직인 채 떼면 그 줄 하나만 토글하고 끌기는 시작하지 않는다")
  func shortMoveThenReleaseToggles() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()
    let tracker = Self.tracker()
    let start = CGPoint(x: 20, y: Self.midY("estimated"))

    Self.touch(tracker, start: start, to: start, model: model)
    Self.touch(tracker, start: start, to: CGPoint(x: 24, y: start.y + 5), model: model)
    #expect(tracker.phase == .pending("estimated"))
    #expect(!model.isDragSelecting)

    tracker.touchEnded(model: model)
    #expect(model.selectedIDs == ["expired", "estimated", "used"])
    #expect(tracker.phase == .idle)

    await cancelAndWait(appear)
  }

  @Test("끌기 거리 이상 움직이면 시작 줄 방향으로 끌기를 시작하고, 떼면 끌기만 끝나 토글하지 않는다")
  func moveBeyondDistanceStartsDrag() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()
    let tracker = Self.tracker()
    let start = CGPoint(x: 20, y: Self.midY("expired"))

    Self.touch(tracker, start: start, to: start, model: model)
    Self.touch(
      tracker,
      start: start,
      to: CGPoint(x: 20, y: start.y + CleanupDragGeometry.dragStartDistance),
      model: model
    )
    #expect(tracker.phase == .dragging("expired"))
    #expect(model.isDragSelecting)
    // 시작 줄 `expired` 가 선택돼 있어 해제 방향이다.
    #expect(model.selectedIDs == ["used"])

    Self.touch(tracker, start: start, to: CGPoint(x: 20, y: Self.midY("used")), model: model)
    #expect(model.selectedIDs == [])

    tracker.touchEnded(model: model)
    #expect(!model.isDragSelecting)
    #expect(model.selectedIDs == [])
    #expect(tracker.phase == .idle)

    await cancelAndWait(appear)
  }

  @Test("누른 뒤 끌기 전에 시스템이 터치를 가져가면 토글하지 않는다")
  func cancelWhilePendingDoesNotToggle() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()
    let tracker = Self.tracker()
    let start = CGPoint(x: 20, y: Self.midY("estimated"))

    Self.touch(tracker, start: start, to: start, model: model)
    #expect(tracker.phase == .pending("estimated"))

    tracker.touchCancelled(model: model)
    #expect(model.selectedIDs == ["expired", "used"])
    #expect(tracker.phase == .idle)

    await cancelAndWait(appear)
  }

  @Test("체크 원 밖에서 시작한 누름은 따르지 않아 떼도 아무것도 바뀌지 않는다")
  func touchOutsideCircleIsIgnored() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()
    let tracker = Self.tracker()
    let start = CGPoint(x: 200, y: Self.midY("estimated"))

    Self.touch(tracker, start: start, to: start, model: model)
    Self.touch(tracker, start: start, to: CGPoint(x: 200, y: Self.midY("used")), model: model)
    #expect(tracker.phase == .idle)

    tracker.touchEnded(model: model)
    #expect(model.selectedIDs == ["expired", "used"])
    #expect(!model.isDragSelecting)

    await cancelAndWait(appear)
  }

  @Test("시작 줄이 사라져 Model 이 끌기를 먼저 끝내면, 뒤따른 이동과 손 뗌은 선택을 바꾸지 않는다")
  func moveAfterModelEndedDragIsIgnored() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()
    let tracker = Self.tracker()
    let start = CGPoint(x: 20, y: Self.midY("estimated"))

    Self.touch(tracker, start: start, to: start, model: model)
    Self.touch(tracker, start: start, to: CGPoint(x: 20, y: start.y + 10), model: model)
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    try await photoStore.delete(ids: ["estimated"])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("estimated") == false }
    #expect(!model.isDragSelecting)
    let selected = model.selectedIDs

    Self.touch(tracker, start: start, to: CGPoint(x: 20, y: Self.midY("expired")), model: model)
    Self.touch(tracker, start: start, to: CGPoint(x: 20, y: Self.midY("used")), model: model)
    tracker.touchEnded(model: model)
    #expect(model.selectedIDs == selected)
    #expect(tracker.phase == .idle)

    await cancelAndWait(appear)
  }
}
