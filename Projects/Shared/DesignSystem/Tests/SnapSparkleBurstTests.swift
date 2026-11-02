import DesignSystem
import SwiftUI
import Testing

@MainActor
struct SnapSparkleBurstTests {
  @Test("한 번 터지고 끝나면 투명하다")
  func burstsOnceAndFades() {
    let timeline = KeyframeTimeline(initialValue: SnapSparkleBurst.Burst.finished) {
      SnapSparkleBurst.keyframes
    }
    #expect(abs(timeline.duration - SnapSparkleBurst.duration) < 0.0001)

    let start = timeline.value(time: 0)
    #expect(start.spread < 0.0001)
    #expect(start.opacity < 0.0001)

    let middle = timeline.value(time: SnapSparkleBurst.duration * 0.3)
    #expect(middle.opacity > 0.9)
    #expect(middle.spread > 0)

    let end = timeline.value(time: SnapSparkleBurst.duration)
    #expect(abs(end.spread - 1) < 0.0001)
    #expect(end.opacity < 0.0001)
    #expect(SnapSparkleBurst.Burst.finished.opacity == 0)
  }
}
