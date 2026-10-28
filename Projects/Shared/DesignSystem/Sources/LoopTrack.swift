import Foundation
import SwiftUI

/// 한 주기(0~1)를 도는 값의 키프레임. 키 사이는 ease-in-out 으로 잇고, 주기를 넘는 시각은 접는다(CSS `@keyframes` 와 같다).
/// 진행 그림이 `TimelineView` 시각에서 위치·크기·투명도를 계산할 때 쓴다. 키는 시각 0 과 1 을 포함해 오름차순으로 준다.
public struct LoopTrack: Sendable {
  private let keys: [(time: Double, value: Double)]

  public init(_ keys: KeyValuePairs<Double, Double>) {
    self.keys = keys.map { (time: $0.key, value: $0.value) }
  }

  /// `cycle` 은 주기 단위 시각이다(1 = 한 바퀴). 음수도 접는다.
  public func value(at cycle: Double) -> Double {
    guard let first = self.keys.first, let last = self.keys.last else { return 0 }
    let time = cycle - cycle.rounded(.down)
    guard let upper = self.keys.firstIndex(where: { $0.time >= time }) else { return last.value }
    guard upper > 0 else { return first.value }
    let start = self.keys[upper - 1]
    let end = self.keys[upper]
    let span = end.time - start.time
    let local = span > 0 ? (time - start.time) / span : 1
    let eased = local * local * (3 - 2 * local)
    return start.value + (end.value - start.value) * eased
  }
}

/// 반복 그림의 시계. 동작 줄이기(Reduce Motion)면 `stillTime` 한 장면에 멈춘다.
/// 장식 움직임이라 초당 30번까지만 다시 그려, 인덱싱이 오래 이어져도 그리기 부담을 줄인다.
struct LoopingTimeline<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// 동작 줄이기에서 보일 시각(초).
  let stillTime: TimeInterval
  @ViewBuilder let content: (TimeInterval) -> Content

  var body: some View {
    if self.reduceMotion {
      self.content(self.stillTime)
    } else {
      TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
        self.content(context.date.timeIntervalSinceReferenceDate)
      }
    }
  }
}

/// 고정 크기로 그린 그림을 주어진 폭에 맞춰 줄인다(늘리지는 않는다). 좁은 기기에서도 그림 배치가 깨지지 않는다.
struct FittedArt<Content: View>: View {
  let size: CGSize
  @ViewBuilder let content: () -> Content

  var body: some View {
    GeometryReader { proxy in
      self.content()
        .frame(width: self.size.width, height: self.size.height)
        .scaleEffect(proxy.size.width / self.size.width, anchor: .topLeading)
    }
    .aspectRatio(self.size.width / self.size.height, contentMode: .fit)
    .frame(maxWidth: self.size.width)
  }
}
