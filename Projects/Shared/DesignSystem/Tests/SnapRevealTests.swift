import DesignSystem
import Testing

struct SnapRevealTests {
  @Test("순서마다 0.04초씩 늦게 시작하고 상한에서 멈춘다")
  func delaysByIndexUpToCap() {
    #expect(SnapReveal.step == 0.04)
    #expect(SnapReveal.delay(index: 0) == 0)
    #expect(abs(SnapReveal.delay(index: 1) - 0.04) < 0.0001)
    #expect(abs(SnapReveal.delay(index: 5) - 0.2) < 0.0001)
    let cap = SnapReveal.delay(index: SnapReveal.maxSteps)
    #expect(abs(cap - Double(SnapReveal.maxSteps) * SnapReveal.step) < 0.0001)
    #expect(SnapReveal.delay(index: SnapReveal.maxSteps + 1) == cap)
    #expect(SnapReveal.delay(index: 100) == cap)
    #expect(SnapReveal.delay(index: -1) == 0)
  }
}
