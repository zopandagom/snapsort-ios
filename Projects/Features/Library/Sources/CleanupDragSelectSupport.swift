import Core
import CoreGraphics
import Observation
import SwiftUI

/// 정리 화면의 체크 원 끌어 선택을 돕는 View 일시 상태 (docs/ARCHITECTURE.md §4 정리 도우미 선택).
/// 선택 규칙은 모두 `CleanupModel` 의 끌기 이벤트에 있고, 여기서는 손가락 위치를 후보 줄로 바꾸고 목록 끝에서 자동 스크롤한다
/// (순수 계산은 `CleanupDragGeometry.swift`). 끌기는 List 위에 덧댄 체크 원 열 오버레이(`CleanupCheckColumnOverlay`)가 받는다.
/// 줄(셀)에 단 제스처는 자동 스크롤로 시작 줄이 화면 밖으로 나가 셀이 떼어지면 취소된다.

/// 보이는 체크 원 frame 과 손 스크롤 막기. 오버레이만 읽어, 스크롤 프레임마다 frame 이 바뀌어도 정리 화면 몸체는 다시 그리지 않는다.
@MainActor
@Observable
final class CleanupCheckColumn {
  /// 보이는 체크 원의 전역 frame. 사라진 줄은 지운다.
  var frames: [ImageAsset.ID: CGRect] = [:]
  /// 사용자 스크롤로 체크 원 열을 막는 중. 막는 동안 오버레이는 터치를 받지 않는다.
  private(set) var isScrolling = false

  @ObservationIgnored private var block = CleanupScrollBlock()
  /// 막기를 푸는 Task. 막기가 서 있는 동안 하나만 돈다(오프셋 변화는 `blockedUntil` 만 늘린다).
  @ObservationIgnored private var unblockTask: Task<Void, Never>?

  /// 목록 오프셋이 바뀌었다. `isOwnScroll` 이면(우리 자동 스크롤) 막지 않는다.
  func offsetChanged(isOwnScroll: Bool) {
    let now = ContinuousClock.now
    self.block.offsetChanged(at: now, isOwnScroll: isOwnScroll)
    guard self.block.isBlocked(at: now) else { return }
    if !self.isScrolling {
      self.isScrolling = true
    }
    guard self.unblockTask == nil else { return }
    self.unblockTask = Task { [weak self] in
      while !Task.isCancelled, let until = self?.block.blockedUntil, ContinuousClock.now < until {
        try? await Task.sleep(until: until, clock: .continuous)
      }
      guard !Task.isCancelled, let self else { return }
      self.unblockTask = nil
      self.isScrolling = false
    }
  }

  /// 화면이 사라졌다. 돌아온 직후 끌기가 스크롤로 오인되지 않게 막기를 푼다.
  func reset() {
    self.unblockTask?.cancel()
    self.unblockTask = nil
    self.block.reset()
    if self.isScrolling {
      self.isScrolling = false
    }
  }
}

/// 체크 원 누름·끌기 추적과 자동 스크롤. 관찰하지 않는 참조라 줄 frame 이 스크롤 프레임마다 바뀌어도 화면을 다시 그리지 않는다.
/// 선택은 모두 Model 이벤트로 넘긴다.
@MainActor
final class CleanupDragTracker {
  enum Phase: Equatable {
    case idle
    /// 체크 원을 눌렀고 아직 끌기 거리만큼 움직이지 않았다. 이대로 떼면 탭이다.
    case pending(ImageAsset.ID)
    case dragging(ImageAsset.ID)
  }

  private(set) var phase: Phase = .idle
  /// 보이는 후보 줄의 전역 frame. 사라진 줄은 지운다.
  var rowFrames: [ImageAsset.ID: CGRect] = [:]
  /// 목록의 전역 frame(내비 바·도구 막대 영역은 빠진다). 보이는 영역으로 쓴다.
  var listFrame: CGRect = .zero
  /// 화면 순서의 후보 식별자.
  var order: [ImageAsset.ID] = [] {
    didSet { self.orderIDs = Set(self.order) }
  }

  private(set) var orderIDs: Set<ImageAsset.ID> = []
  var proxy: ScrollViewProxy?

  private var fingerY: CGFloat?
  private var scrollTask: Task<Void, Never>?
  /// 마지막 단계 스크롤 애니메이션이 끝나는 시각.
  private var ownScrollUntil: ContinuousClock.Instant?

  /// 지금 오프셋 변화가 우리 자동 스크롤인지(`CleanupScrollBlock.ownsScroll`).
  func ownsScroll() -> Bool {
    CleanupScrollBlock.ownsScroll(isTracking: self.phase != .idle, ownScrollUntil: self.ownScrollUntil, now: .now)
  }

  /// 오버레이 제스처가 움직였다. 체크 원에서 시작한 누름만 따르고, 끌기 거리를 넘으면 끌기를 시작한다.
  func touchChanged(start: CGPoint, location: CGPoint, circles: [ImageAsset.ID: CGRect], model: CleanupModel) {
    switch self.phase {
    case .idle:
      guard let id = CleanupDragGeometry.checkCircleID(at: start, circles: circles, known: self.orderIDs)
      else { return }
      self.phase = .pending(id)
    case let .pending(id):
      guard hypot(location.x - start.x, location.y - start.y) >= CleanupDragGeometry.dragStartDistance else { return }
      model.dragSelectionBegan(id: id)
      self.phase = .dragging(id)
      self.fingerY = location.y
      self.fingerMoved(model: model)
    case .dragging:
      self.fingerY = location.y
      self.fingerMoved(model: model)
    }
  }

  /// 손을 뗐다. 끌기 전이면 탭이라 그 줄 하나를 토글한다.
  func touchEnded(model: CleanupModel) {
    if case let .pending(id) = self.phase {
      model.candidateToggled(id: id)
    }
    self.finish(model: model)
  }

  /// 시스템이 터치를 가져갔거나 화면이 사라졌다. 탭으로 치지 않는다. 이미 끝났으면 아무것도 하지 않는다.
  func touchCancelled(model: CleanupModel) {
    self.finish(model: model)
  }

  /// 줄 frame 이 바뀌었다(자동 스크롤·레이아웃 변경). 끌기 중이면 손가락 아래 줄을 다시 본다.
  func rowFrameChanged(id: ImageAsset.ID, frame: CGRect, model: CleanupModel) {
    self.rowFrames[id] = frame
    guard case .dragging = self.phase else { return }
    self.updateRow(model: model)
  }

  private func finish(model: CleanupModel) {
    if case .dragging = self.phase {
      model.dragSelectionEnded()
    }
    self.phase = .idle
    self.fingerY = nil
    self.scrollTask?.cancel()
    self.scrollTask = nil
  }

  private func fingerMoved(model: CleanupModel) {
    self.updateRow(model: model)
    guard self.scrollTask == nil, model.isDragSelecting, self.speed() != 0 else { return }
    self.startAutoScroll(model: model)
  }

  private var rows: [CleanupDragGeometry.Row] {
    self.rowFrames
      .filter { self.orderIDs.contains($0.key) }
      .map { CleanupDragGeometry.Row(id: $0.key, minY: $0.value.minY, maxY: $0.value.maxY) }
  }

  private var visibleArea: CleanupDragGeometry.VisibleArea {
    CleanupDragGeometry.VisibleArea(top: self.listFrame.minY, bottom: self.listFrame.maxY)
  }

  private func speed() -> CGFloat {
    guard let fingerY = self.fingerY else { return 0 }
    return CleanupDragGeometry.autoScrollSpeed(fingerY: fingerY, visible: self.visibleArea)
  }

  /// 손가락 아래 후보 줄을 Model 에 알린다. Model 이 끌기를 끝냈으면 부르지 않는다.
  private func updateRow(model: CleanupModel) {
    guard model.isDragSelecting, let fingerY = self.fingerY,
          let id = CleanupDragGeometry.candidateID(atY: fingerY, rows: self.rows, visible: self.visibleArea)
    else { return }
    model.dragSelectionMoved(to: id)
  }

  /// 손가락이 끝 영역에 있는 동안 16ms 마다 이동 거리를 쌓아, 줄 높이만큼 쌓이면 다음 후보 줄까지 짧은 애니메이션으로 스크롤한다
  /// (List 는 `ScrollPosition` 으로 움직이지 않아 `ScrollViewReader` 단계 스크롤을 쓴다). 영역 밖·후보 끝·손 뗌·Model 이 끌기를 끝냄에서 멈춘다.
  private func startAutoScroll(model: CleanupModel) {
    self.scrollTask = Task { [weak self] in
      let clock = ContinuousClock()
      var last = clock.now
      var distance: CGFloat = 0
      var target: ImageAsset.ID?
      var downward: Bool?
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(16))
        guard let self, !Task.isCancelled, case .dragging = self.phase, model.isDragSelecting else { break }
        let now = clock.now
        let elapsed = min(Double((now - last) / .seconds(1)), 0.05)
        last = now
        let speed = self.speed()
        guard speed != 0 else { break }
        // 방향이 바뀌면 지난 목표에서 이어 가지 않는다.
        let isDownward = speed > 0
        if downward != isDownward {
          downward = isDownward
          target = nil
          distance = 0
        }
        guard let next = CleanupDragGeometry.nextScrollTarget(
          order: self.order,
          rows: self.rows,
          visible: self.visibleArea,
          downward: isDownward,
          after: target
        ) else { break }
        distance += abs(speed) * elapsed
        let step = self.rowFrames[next]?.height ?? 72
        guard distance >= step else { continue }
        distance -= step
        target = next
        // 체크 전환 애니메이션을 넣지 않게 클로저 안에는 스크롤만 둔다.
        let duration = min(max(step / abs(speed), 0.05), 0.2)
        withAnimation(.linear(duration: duration)) {
          self.proxy?.scrollTo(next, anchor: isDownward ? .bottom : .top)
        }
        self.ownScrollUntil = .now + .seconds(duration)
        self.updateRow(model: model)
      }
      if !Task.isCancelled {
        self?.scrollTask = nil
      }
    }
  }
}

/// List 위에 덧댄 체크 원 열. 보이는 체크 원 위 터치만 받고(나머지는 아래 List 로 간다), 탭은 토글, 끌기는 범위 선택이다.
/// 접근성에서는 숨긴다(VoiceOver 는 끌기 없이 체크 원 버튼·"모두 선택"을 쓴다). 사용자 스크롤로 막힌 동안은 아무 터치도 받지 않는다.
struct CleanupCheckColumnOverlay: View {
  let model: CleanupModel
  let checkColumn: CleanupCheckColumn
  let tracker: CleanupDragTracker
  /// 화면 순서의 후보 식별자. `tracker.order` 는 관찰하지 않으므로, 새 후보의 누름 영역이 순서 갱신을 기다리지 않게 인자로 받는다.
  let candidateIDs: Set<ImageAsset.ID>

  @State private var frame: CGRect = .zero
  @GestureState private var isTouching = false

  var body: some View {
    let rects = self.checkColumn.isScrolling
      ? []
      : CleanupDragGeometry.touchRects(
        circles: self.checkColumn.frames,
        known: self.candidateIDs,
        overlay: self.frame
      )
    Color.clear
      .contentShape(Path { $0.addRects(rects) })
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
          .updating(self.$isTouching) { _, state, _ in state = true }
          .onChanged { value in
            self.tracker.touchChanged(
              start: value.startLocation,
              location: value.location,
              circles: self.checkColumn.frames,
              model: self.model
            )
          }
          .onEnded { _ in self.tracker.touchEnded(model: self.model) }
      )
      .onChange(of: self.isTouching) { _, isTouching in
        // `onEnded` 없이 풀렸으면 시스템이 터치를 가져간 것이다. `onEnded` 가 먼저 왔으면 이미 끝나 아무것도 하지 않는다.
        if !isTouching {
          self.tracker.touchCancelled(model: self.model)
        }
      }
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { self.frame = $0 }
      .accessibilityHidden(true)
  }
}
