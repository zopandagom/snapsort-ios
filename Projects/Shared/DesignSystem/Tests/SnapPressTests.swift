import DesignSystem
import Testing

struct SnapPressTests {
  @Test("누르지 않으면 크기·불투명도가 그대로다")
  func restingIsIdentity() {
    for reduceMotion in [false, true] {
      let effect = SnapPress.effect(isPressed: false, reduceMotion: reduceMotion)
      #expect(effect.scale == 1)
      #expect(effect.opacity == 1)
    }
  }

  @Test("누르면 살짝 작아지고 흐려지지 않는다")
  func pressedShrinks() {
    let effect = SnapPress.effect(isPressed: true, reduceMotion: false)
    #expect(effect.scale == SnapPress.pressedScale)
    #expect(effect.scale < 1 && effect.scale >= 0.9)
    #expect(effect.opacity == 1)
  }

  @Test("동작 줄이기면 크기는 그대로 두고 흐려지기만 한다")
  func reduceMotionOnlyDims() {
    let effect = SnapPress.effect(isPressed: true, reduceMotion: true)
    #expect(effect.scale == 1)
    #expect(effect.opacity == SnapPress.reducedPressedOpacity)
    #expect(effect.opacity < 1)
  }
}
