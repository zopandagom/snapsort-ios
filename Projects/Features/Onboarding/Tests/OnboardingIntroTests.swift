import Testing
@testable import OnboardingFeature

struct OnboardingIntroTests {
  private static let steps: [OnboardingIntro.Step] = [
    .mark,
    .title,
    .feature(0),
    .feature(1),
    .feature(2),
    .privacy,
    .startButton,
  ]

  @Test("앱 마크 → 제목 → 기능 세 줄 → 개인정보 줄 → 시작 버튼 순서로 늦게 나타난다", arguments: [false, true])
  func appearsInOrder(reduceMotion: Bool) {
    let delays = Self.steps.map { OnboardingIntro.delay($0, reduceMotion: reduceMotion) }
    #expect(delays == delays.sorted())
    #expect(Set(delays).count == delays.count)
    #expect(OnboardingIntro.glowDelay(reduceMotion: reduceMotion) > (delays.last ?? 0))
  }

  @Test("기본 시간: 제목 0.25초, 기능 줄 0.52초부터 0.15초 간격, 개인정보 1.05초, 시작 버튼 1.15초")
  func defaultTimings() {
    #expect(OnboardingIntro.delay(.mark, reduceMotion: false) == 0)
    #expect(OnboardingIntro.delay(.title, reduceMotion: false) == 0.25)
    #expect(abs(OnboardingIntro.delay(.feature(2), reduceMotion: false) - 0.82) < 0.0001)
    #expect(OnboardingIntro.delay(.privacy, reduceMotion: false) == 1.05)
    #expect(OnboardingIntro.delay(.startButton, reduceMotion: false) == 1.15)
  }

  @Test("동작 줄이기면 0.06초 간격으로 투명도만 바뀐다")
  func reducedMotionSteps() {
    for (order, step) in Self.steps.enumerated() {
      #expect(abs(OnboardingIntro.delay(step, reduceMotion: true) - Double(order) * 0.06) < 0.0001)
    }
  }
}
