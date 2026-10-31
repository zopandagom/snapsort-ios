import DesignSystem
import SwiftUI
import Testing

@MainActor
struct SnapGlowTests {
  private var timeline: KeyframeTimeline<Double> {
    KeyframeTimeline(initialValue: SnapGlow.restLevel) {
      SnapGlow.keyframes
    }
  }

  @Test("세 번 번지는 동안 반 주기마다 가장 밝고, 주기마다 꺼진다")
  func pulsesThreeTimes() {
    let period = SnapGlow.period
    for pulse in 0 ..< 3 {
      let start = period * Double(pulse)
      #expect(abs(self.timeline.value(time: start + period / 2) - 1) < 0.0001)
      if pulse < 2 {
        #expect(abs(self.timeline.value(time: start + period)) < 0.0001)
      }
    }
  }

  @Test("세 주기 뒤에는 쉼 세기로 멈춘다")
  func settlesAtRestLevel() {
    #expect(abs(self.timeline.duration - SnapGlow.period * 3) < 0.0001)
    #expect(abs(self.timeline.value(time: SnapGlow.period * 3) - SnapGlow.restLevel) < 0.0001)
    #expect(abs(self.timeline.value(time: SnapGlow.period * 10) - SnapGlow.restLevel) < 0.0001)
    #expect(SnapGlow.restLevel > 0 && SnapGlow.restLevel < 1)
  }

  @Test("돌기 전 세기와 끝난 뒤 세기가 같아, 키프레임 앞뒤로 빛이 튀지 않는다")
  func startsAtRestLevel() {
    #expect(abs(self.timeline.value(time: 0) - SnapGlow.restLevel) < 0.0001)
  }
}
