import CoreGraphics
import Foundation
import Testing
@testable import LibraryFeature

/// 정리 화면 체크 원 끌기의 순수 계산: 손가락 위치→후보 줄, 끝 영역 깊이→자동 스크롤 속도, 단계 스크롤 목표, 체크 원 누름 영역,
/// 손 스크롤 막기 (docs/ARCHITECTURE.md §4 정리 도우미 선택). 보이는 영역은 y 100~700 이다.
struct CleanupDragGeometryTests {
  static let visible = CleanupDragGeometry.VisibleArea(top: 100, bottom: 700)

  /// 높이 70 줄 셋: r1 100~170, r2 180~250(틈 10), r3 250~320.
  static let rows: [CleanupDragGeometry.Row] = [
    .init(id: "r1", minY: 100, maxY: 170),
    .init(id: "r2", minY: 180, maxY: 250),
    .init(id: "r3", minY: 250, maxY: 320),
  ]

  static func candidate(atY y: CGFloat, rows: [CleanupDragGeometry.Row] = Self.rows) -> String? {
    CleanupDragGeometry.candidateID(atY: y, rows: rows, visible: self.visible)
  }

  static func speed(_ y: CGFloat, top: CGFloat = Self.visible.top, bottom: CGFloat = Self.visible.bottom) -> CGFloat {
    CleanupDragGeometry.autoScrollSpeed(fingerY: y, visible: .init(top: top, bottom: bottom))
  }

  // MARK: - 위치 → 줄

  @Test("손가락 높이를 품은 줄을 고르고, 줄 사이 틈이면 가까운 줄, 같은 거리면 위쪽 줄이다")
  func candidateUnderFinger() {
    #expect(Self.candidate(atY: 120) == "r1")
    #expect(Self.candidate(atY: 260) == "r3")
    #expect(Self.candidate(atY: 172) == "r1")
    #expect(Self.candidate(atY: 178) == "r2")
    #expect(Self.candidate(atY: 175) == "r1")
  }

  @Test("모든 줄 아래면 맨 아래 줄, 보이는 영역 위(내비 바)면 보이는 맨 위 줄이다")
  func outsideRowsPicksEdgeRow() {
    #expect(Self.candidate(atY: 600) == "r3")
    #expect(Self.candidate(atY: 40) == "r1")
  }

  @Test("보이는 영역 밖 줄은 고르지 않고, 손가락이 막대 위면 보이는 끝 줄이다")
  func ignoresRowsOutsideVisibleArea() {
    let rows: [CleanupDragGeometry.Row] = [
      .init(id: "above", minY: 0, maxY: 90),
      .init(id: "first", minY: 90, maxY: 160),
      .init(id: "last", minY: 640, maxY: 710),
      .init(id: "hidden", minY: 720, maxY: 790),
    ]
    #expect(Self.candidate(atY: 50, rows: rows) == "first")
    #expect(Self.candidate(atY: 760, rows: rows) == "last")
  }

  @Test("줄이 없거나 보이는 줄이 없으면 nil 이다")
  func noVisibleRowIsNil() {
    #expect(Self.candidate(atY: 300, rows: []) == nil)
    #expect(Self.candidate(atY: 300, rows: [.init(id: "hidden", minY: 720, maxY: 790)]) == nil)
  }

  // MARK: - 자동 스크롤 속도

  @Test("끝 영역 밖은 0, 아래 영역 경계 바로 안은 최소 속도, 끝과 목록 밖은 상한이고 깊어질수록 빨라진다")
  func bottomZoneSpeed() {
    #expect(Self.speed(400) == 0)
    #expect(Self.speed(640) == 0)
    #expect(abs(Self.speed(640.01) - CleanupDragGeometry.minimumSpeed) < 1)
    #expect(Self.speed(700) == CleanupDragGeometry.maximumSpeed)
    #expect(Self.speed(780) == CleanupDragGeometry.maximumSpeed)
    let speeds = stride(from: 645, through: 700, by: 5).map { Self.speed(CGFloat($0)) }
    #expect(zip(speeds, speeds.dropFirst()).allSatisfy { $0 < $1 })
    #expect(Self.speed(670) == CleanupDragGeometry.minimumSpeed
      + (CleanupDragGeometry.maximumSpeed - CleanupDragGeometry.minimumSpeed) * 0.25)
  }

  @Test("위 영역은 위로(음수) 같은 크기다")
  func topZoneSpeedIsNegative() {
    #expect(Self.speed(160) == 0)
    #expect(Self.speed(130) == -Self.speed(670))
    #expect(Self.speed(20) == -CleanupDragGeometry.maximumSpeed)
  }

  @Test("짧은 목록에서는 끝 영역이 높이의 1/4 이라 위아래가 겹치지 않는다")
  func shortListZone() {
    // 높이 160 → 영역 40.
    #expect(Self.speed(150, top: 100, bottom: 260) == 0)
    #expect(Self.speed(139, top: 100, bottom: 260) < 0)
    #expect(Self.speed(221, top: 100, bottom: 260) > 0)
    #expect(Self.speed(180, top: 100, bottom: 260) == 0)
  }

  // MARK: - 단계 스크롤 목표

  static let order = ["c1", "c2", "c3", "c4", "c5"]
  /// c2 는 위 끝에 일부만, c3·c4 는 다 보이고 c5 는 아래 끝에 일부만 보인다.
  static let scrollRows: [CleanupDragGeometry.Row] = [
    .init(id: "c2", minY: 60, maxY: 130),
    .init(id: "c3", minY: 300, maxY: 370),
    .init(id: "c4", minY: 400, maxY: 470),
    .init(id: "c5", minY: 650, maxY: 720),
  ]

  static func target(
    rows: [CleanupDragGeometry.Row] = Self.scrollRows,
    downward: Bool,
    after previous: String? = nil
  ) -> String? {
    CleanupDragGeometry.nextScrollTarget(
      order: self.order,
      rows: rows,
      visible: self.visible,
      downward: downward,
      after: previous
    )
  }

  @Test("지난 목표가 없으면 다 보이는 끝 후보의 다음(위면 앞) 후보다")
  func targetFromFullyVisibleEdge() {
    #expect(Self.target(downward: true) == "c5")
    #expect(Self.target(downward: false) == "c2")
  }

  @Test("지난 목표가 있으면 그 다음(위면 앞) 후보로 이어 간다")
  func targetContinuesFromPrevious() {
    #expect(Self.target(downward: true, after: "c5") == nil)
    #expect(Self.target(downward: true, after: "c3") == "c4")
    #expect(Self.target(downward: false, after: "c2") == "c1")
  }

  @Test("다 보이는 후보가 없으면 일부라도 보이는 후보 기준이고, 지난 목표가 순서에 없으면 화면으로 다시 고른다")
  func targetFromPartiallyVisible() {
    let rows: [CleanupDragGeometry.Row] = [.init(id: "c2", minY: 50, maxY: 750)]
    #expect(Self.target(rows: rows, downward: true) == "c3")
    #expect(Self.target(rows: rows, downward: false) == "c1")
    #expect(Self.target(downward: true, after: "gone") == "c5")
  }

  @Test("후보 끝이거나 보이는 후보가 없으면 nil 이라 멈춘다")
  func targetAtEndIsNil() {
    let lastVisible: [CleanupDragGeometry.Row] = [.init(id: "c5", minY: 300, maxY: 370)]
    let firstVisible: [CleanupDragGeometry.Row] = [.init(id: "c1", minY: 300, maxY: 370)]
    #expect(Self.target(rows: lastVisible, downward: true) == nil)
    #expect(Self.target(rows: firstVisible, downward: false) == nil)
    #expect(Self.target(rows: [], downward: true) == nil)
  }

  // MARK: - 체크 원 누름 영역

  static let circles: [String: CGRect] = [
    "c1": CGRect(x: 32, y: 120, width: 44, height: 44),
    "c2": CGRect(x: 32, y: 200, width: 44, height: 44),
    "stale": CGRect(x: 32, y: 280, width: 44, height: 44),
  ]

  @Test("점을 품은 체크 원을 고르고, 어느 체크 원에도 없거나 화면 순서에 없는 후보의 낡은 frame 이면 nil 이다")
  func checkCircleUnderPoint() {
    let known: Set = ["c1", "c2"]
    #expect(CleanupDragGeometry.checkCircleID(at: CGPoint(x: 50, y: 210), circles: Self.circles, known: known) == "c2")
    #expect(CleanupDragGeometry.checkCircleID(at: CGPoint(x: 200, y: 210), circles: Self.circles, known: known) == nil)
    #expect(CleanupDragGeometry.checkCircleID(at: CGPoint(x: 50, y: 290), circles: Self.circles, known: known) == nil)
  }

  @Test("누름 영역은 화면 순서의 체크 원을 오버레이 좌표로 옮겨 오버레이 안에 든 부분만이다")
  func touchRectsInOverlay() {
    let overlay = CGRect(x: 0, y: 140, width: 400, height: 100)
    let rects = CleanupDragGeometry.touchRects(circles: Self.circles, known: ["c1", "c2"], overlay: overlay)
    #expect(rects == [
      CGRect(x: 32, y: 0, width: 44, height: 24),
      CGRect(x: 32, y: 60, width: 44, height: 40),
    ])
    let below = CGRect(x: 0, y: 400, width: 400, height: 100)
    #expect(CleanupDragGeometry.touchRects(circles: Self.circles, known: ["c1", "c2"], overlay: below).isEmpty)
  }

  // MARK: - 손 스크롤 막기

  @Test("우리 스크롤이 아닌 변화는 막기 시간 동안 막고, 지나면 풀며, 변화가 이어지면 마지막 변화부터 다시 잰다")
  func userScrollBlocks() {
    let start = ContinuousClock.now
    var block = CleanupScrollBlock()
    #expect(!block.isBlocked(at: start))

    block.offsetChanged(at: start, isOwnScroll: false)
    #expect(block.isBlocked(at: start + .milliseconds(100)))
    #expect(!block.isBlocked(at: start + .milliseconds(150)))

    block.offsetChanged(at: start + .milliseconds(100), isOwnScroll: false)
    #expect(block.isBlocked(at: start + .milliseconds(200)))
    #expect(!block.isBlocked(at: start + .milliseconds(250)))
  }

  @Test("우리 자동 스크롤의 변화는 막지 않고, 화면이 사라지면 막기를 푼다")
  func ownScrollAndResetDoNotBlock() {
    let start = ContinuousClock.now
    var block = CleanupScrollBlock()
    block.offsetChanged(at: start, isOwnScroll: true)
    #expect(!block.isBlocked(at: start))

    block.offsetChanged(at: start, isOwnScroll: false)
    block.reset()
    #expect(!block.isBlocked(at: start))
  }

  @Test("누름·끌기 중이거나 마지막 단계 스크롤 애니메이션이 끝나기 전이면 우리 스크롤로 보고, 자동 스크롤 없이 끝난 끌기는 여유가 없다")
  func ownsScrollWhileTrackingOrAnimating() {
    let now = ContinuousClock.now
    #expect(CleanupScrollBlock.ownsScroll(isTracking: true, ownScrollUntil: nil, now: now))
    #expect(!CleanupScrollBlock.ownsScroll(isTracking: false, ownScrollUntil: nil, now: now))
    let until = now + .milliseconds(200)
    #expect(CleanupScrollBlock.ownsScroll(isTracking: false, ownScrollUntil: until, now: now + .milliseconds(150)))
    #expect(!CleanupScrollBlock.ownsScroll(isTracking: false, ownScrollUntil: until, now: until))
  }

  @MainActor
  @Test("체크 원 열은 사용자 스크롤에 막히고, 화면이 사라지면 바로 풀린다")
  func checkColumnResetUnblocks() {
    let column = CleanupCheckColumn()
    column.offsetChanged(isOwnScroll: true)
    #expect(!column.isScrolling)
    column.offsetChanged(isOwnScroll: false)
    #expect(column.isScrolling)
    column.reset()
    #expect(!column.isScrolling)
  }

  @MainActor
  @Test("체크 원 열 막기는 마지막 변화 뒤 막기 시간이 지나면 풀린다")
  func checkColumnUnblocksAfterDuration() async {
    let column = CleanupCheckColumn()
    column.offsetChanged(isOwnScroll: false)
    #expect(column.isScrolling)
    await waitUntil { !column.isScrolling }
  }
}
