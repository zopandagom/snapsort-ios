import DesignSystem
import SwiftUI
import Testing

@MainActor
struct SnapStampTests {
  private var timeline: KeyframeTimeline<SnapStamp.Pose> {
    KeyframeTimeline(initialValue: SnapStamp.restingPose) {
      SnapStamp.keyframes
    }
  }

  @Test("도장 키프레임은 크게 시작해 쉬는 크기·각도로 끝난다")
  func stampsFromLargeToRest() {
    let start = self.timeline.value(time: 0)
    let initial = SnapStamp.initialPose(reduceMotion: false)
    #expect(abs(start.scale - initial.scale) < 0.0001)
    #expect(start.scale > 1)
    #expect(abs(start.degrees - initial.degrees) < 0.0001)
    #expect(start.degrees < SnapStamp.restAngle.degrees)
    #expect(start.opacity < 0.0001)

    #expect(abs(self.timeline.duration - SnapStamp.duration) < 0.0001)
    let end = self.timeline.value(time: SnapStamp.duration)
    #expect(abs(end.scale - 1) < 0.001)
    #expect(abs(end.degrees - SnapStamp.restAngle.degrees) < 0.0001)
    #expect(abs(end.opacity - 1) < 0.0001)
    #expect(SnapStamp.restingPose == SnapStamp.Pose(scale: 1, degrees: SnapStamp.restAngle.degrees, opacity: 1))
  }

  @Test("동작 줄이기면 크기 1·쉬는 각도로 고정된다")
  func reduceMotionKeepsRestingShape() {
    let initial = SnapStamp.initialPose(reduceMotion: true)
    #expect(initial.scale == 1)
    #expect(initial.degrees == SnapStamp.restAngle.degrees)
    #expect(initial.opacity == 0)
  }
}
