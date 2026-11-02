import DesignSystem
import Testing

struct SnapPulseTests {
  @Test("켜져 있고 동작 줄이기가 아니면 1 과 최고 배율을 오간다")
  func pulsesWhenActive() {
    #expect(SnapPulse.phases(isActive: true, reduceMotion: false) == [1, SnapPulse.peakScale])
    #expect(SnapPulse.period > 0)
  }

  @Test("동작 줄이기이거나 꺼져 있으면 움직이지 않는다")
  func staysStillOtherwise() {
    #expect(SnapPulse.phases(isActive: true, reduceMotion: true) == [1])
    #expect(SnapPulse.phases(isActive: false, reduceMotion: false) == [1])
    #expect(SnapPulse.phases(isActive: false, reduceMotion: true) == [1])
  }

  @Test("최고 배율은 1 보다 크고 1.1 이하다")
  func peakScaleIsSubtle() {
    #expect(SnapPulse.peakScale > 1)
    #expect(SnapPulse.peakScale <= 1.1)
  }
}
