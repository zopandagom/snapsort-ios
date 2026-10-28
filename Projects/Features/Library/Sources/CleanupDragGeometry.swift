import Core
import CoreGraphics

/// 정리 화면 체크 원 끌어 선택의 순수 계산 (docs/ARCHITECTURE.md §4 정리 도우미 선택).
/// 손가락 위치→후보 줄, 끝 영역 깊이→자동 스크롤 속도, 단계 스크롤 목표, 체크 원 누름 영역, 손 스크롤 막기.
/// View 일시 상태(`CleanupDragTracker`·`CleanupCheckColumn`)가 `CleanupDragSelectSupport.swift` 에서 부른다.

/// 끌기의 위치·속도 계산. 좌표는 모두 전역(`.global`)이다.
enum CleanupDragGeometry {
  /// 후보 줄 하나의 세로 범위.
  struct Row: Equatable {
    let id: ImageAsset.ID
    let minY: CGFloat
    let maxY: CGFloat
  }

  /// 보이는 영역의 세로 범위(목록 frame 의 위·아래).
  struct VisibleArea: Equatable {
    let top: CGFloat
    let bottom: CGFloat
  }

  /// 대기 중인 누름을 끌기로 볼 이동 거리(pt). 그보다 덜 움직이고 떼면 탭이다.
  static let dragStartDistance: CGFloat = 8
  /// 목록 위·아래 끝 영역 높이(pt). 목록 높이의 1/4 을 넘지 않는다.
  static let edgeZone: CGFloat = 60
  /// 끝 영역 경계와 끝(또는 목록 밖)의 자동 스크롤 속도(pt/s). 그 사이는 깊이의 제곱으로 빨라진다.
  static let minimumSpeed: CGFloat = 120
  static let maximumSpeed: CGFloat = 1200

  /// 손가락 높이 `y` 의 후보 줄. 보이는 영역과 겹치는 줄만 본다(미리 그린 화면 밖 줄이나 막대 아래에 가린 줄을 고르지 않게).
  /// `y` 는 보이는 영역으로 자르고, 그 높이를 품은 줄, 없으면 세로로 가장 가까운 줄(같으면 위쪽 줄). 보이는 줄이 없으면 nil.
  static func candidateID(atY y: CGFloat, rows: [Row], visible area: VisibleArea) -> ImageAsset.ID? {
    let visible = rows.filter { $0.maxY > area.top && $0.minY < area.bottom }
    let y = min(max(y, area.top), area.bottom)
    let distance: (Row) -> CGFloat = { row in
      if y < row.minY {
        row.minY - y
      } else if y > row.maxY {
        y - row.maxY
      } else {
        0
      }
    }
    return visible.min { lhs, rhs in
      let (left, right) = (distance(lhs), distance(rhs))
      return left != right ? left < right : lhs.minY < rhs.minY
    }?.id
  }

  /// 손가락 높이에 따른 자동 스크롤 속도(pt/s). 아래로 +, 위로 −, 끝 영역 밖이면 0. 위 영역을 먼저 본다.
  static func autoScrollSpeed(fingerY: CGFloat, visible area: VisibleArea) -> CGFloat {
    let zone = min(self.edgeZone, (area.bottom - area.top) / 4)
    guard zone > 0 else { return 0 }
    let speed: (CGFloat) -> CGFloat = { depth in
      let fraction = min(depth / zone, 1)
      return self.minimumSpeed + (self.maximumSpeed - self.minimumSpeed) * fraction * fraction
    }
    let topDepth = area.top + zone - fingerY
    if topDepth > 0 {
      return -speed(topDepth)
    }
    let bottomDepth = fingerY - (area.bottom - zone)
    if bottomDepth > 0 {
      return speed(bottomDepth)
    }
    return 0
  }

  /// 자동 스크롤 한 단계에 보일 후보. `previous`(지난 단계 목표)가 `order` 에 있으면 그 다음(위면 앞) 후보다
  /// (매 단계 frame 으로 다시 고르면 애니메이션 중 frame 이 덜 움직여 같은 목표를 되풀이한다).
  /// 없으면 다 보이는 후보 중 화면 순서상 끝 것(위면 첫 것) 기준, 다 보이는 후보가 없으면 일부라도 보이는 후보 기준.
  /// 다음 후보가 없으면 nil(후보 목록 끝, 멈춘다).
  static func nextScrollTarget(
    order: [ImageAsset.ID],
    rows: [Row],
    visible area: VisibleArea,
    downward: Bool,
    after previous: ImageAsset.ID?
  ) -> ImageAsset.ID? {
    let index: Int
    if let previous, let previousIndex = order.firstIndex(of: previous) {
      index = previousIndex
    } else {
      let visible = rows.filter { $0.maxY > area.top && $0.minY < area.bottom }
      let full = visible.filter { $0.minY >= area.top && $0.maxY <= area.bottom }
      let positions = (full.isEmpty ? visible : full).compactMap { row in order.firstIndex(of: row.id) }
      guard let edge = downward ? positions.max() : positions.min() else { return nil }
      index = edge
    }
    let next = downward ? index + 1 : index - 1
    return order.indices.contains(next) ? order[next] : nil
  }

  /// 점을 품은 체크 원. `known`(지금 화면 순서)에 없는 후보의 frame 은 낡은 것이라 보지 않는다. 없으면 nil(그 터치는 무시).
  static func checkCircleID(
    at point: CGPoint,
    circles: [ImageAsset.ID: CGRect],
    known: Set<ImageAsset.ID>
  ) -> ImageAsset.ID? {
    circles
      .filter { known.contains($0.key) && $0.value.contains(point) }
      .min { $0.value.minY < $1.value.minY }?
      .key
  }

  /// 오버레이가 터치를 받을 영역: `known` 후보의 체크 원 frame 을 오버레이 좌표로 옮겨(`overlay` 원점을 뺀다) 오버레이 안에 든 부분만.
  static func touchRects(
    circles: [ImageAsset.ID: CGRect],
    known: Set<ImageAsset.ID>,
    overlay: CGRect
  ) -> [CGRect] {
    let bounds = CGRect(origin: .zero, size: overlay.size)
    return circles
      .filter { known.contains($0.key) }
      .map { $0.value.offsetBy(dx: -overlay.minX, dy: -overlay.minY).intersection(bounds) }
      .filter { !$0.isNull && !$0.isEmpty }
      .sorted { $0.minY < $1.minY }
  }
}

/// 손 스크롤·관성 중 체크 원 열을 막을지. 사용자가 일으킨 오프셋 변화 뒤 `duration` 동안 막아, 그 터치가 목록으로 가게 한다
/// (관성을 멈추려는 탭이 보지 않은 사진을 고르지 않게). 우리 자동 스크롤의 변화는 막지 않는다.
struct CleanupScrollBlock: Equatable {
  /// 마지막 변화 뒤 막는 시간. 관성 중 오프셋은 화면 갱신마다 바뀌므로 이만큼 변화가 없으면 멈춘 것으로 본다(실기기 미조정).
  static let duration: Duration = .milliseconds(150)
  private(set) var blockedUntil: ContinuousClock.Instant?

  /// 오프셋이 바뀌었다. 우리 스크롤이 아니면 마지막 변화부터 다시 `duration` 동안 막는다.
  mutating func offsetChanged(at now: ContinuousClock.Instant, isOwnScroll: Bool) {
    guard !isOwnScroll else { return }
    self.blockedUntil = now + Self.duration
  }

  func isBlocked(at now: ContinuousClock.Instant) -> Bool {
    self.blockedUntil.map { now < $0 } ?? false
  }

  mutating func reset() {
    self.blockedUntil = nil
  }

  /// 지금 오프셋 변화가 우리 자동 스크롤인지: 체크 원 누름·끌기 중이거나, 마지막으로 보낸 단계 스크롤의 애니메이션이 끝나기 전
  /// (`ownScrollUntil` = 보낸 시각 + 애니메이션 길이). 자동 스크롤 없이 끝난 끌기는 여유가 없어, 끌기 직후 손으로 넘긴 관성을 놓치지 않는다.
  static func ownsScroll(
    isTracking: Bool,
    ownScrollUntil: ContinuousClock.Instant?,
    now: ContinuousClock.Instant
  ) -> Bool {
    isTracking || ownScrollUntil.map { now < $0 } == true
  }
}
