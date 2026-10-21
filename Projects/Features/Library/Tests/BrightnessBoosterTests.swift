import CoreGraphics
import Testing
@testable import LibraryFeature

/// 바코드 크게 보기의 밝기 올림·되돌림. 시뮬레이터의 실제 밝기는 바뀌지 않으므로 가짜 화면으로 판단만 본다.
@MainActor
struct BrightnessBoosterTests {
  @Test("보이고 활성이며 화면을 알면 지금 밝기를 기억하고 최대로 올린다")
  func raisesWhenVisibleActiveWithScreen() {
    let screen = FakeScreen(brightness: 0.4)
    let booster = BrightnessBooster<FakeScreen>()

    booster.screenChanged(screen)
    booster.visibilityChanged(true)
    #expect(screen.brightness == 0.4)
    booster.sceneActivityChanged(true)

    #expect(screen.brightness == 1)
    #expect(booster.raised?.savedBrightness == 0.4)
  }

  @Test("화면이 보이기 시작한 뒤에 알려져도 올린다")
  func raisesWhenScreenArrivesAfterAppear() {
    let screen = FakeScreen(brightness: 0.4)
    let booster = BrightnessBooster<FakeScreen>()

    booster.visibilityChanged(true)
    booster.sceneActivityChanged(true)
    #expect(booster.raised == nil)
    booster.screenChanged(screen)

    #expect(screen.brightness == 1)
    #expect(booster.raised?.savedBrightness == 0.4)
  }

  @Test("닫을 때 화면 신호와 사라짐이 어느 순서로 와도 기억한 밝기로 한 번만 되돌린다", arguments: [true, false])
  func restoresOnceInEitherDismissOrder(screenFirst: Bool) {
    let screen = FakeScreen(brightness: 0.4)
    let booster = Self.raisedBooster(on: screen)

    if screenFirst {
      booster.screenChanged(nil)
      booster.visibilityChanged(false)
    } else {
      booster.visibilityChanged(false)
      booster.screenChanged(nil)
    }

    #expect(screen.brightness == 0.4)
    #expect(screen.writes == [1, 0.4])
    #expect(booster.raised == nil)
  }

  @Test("앱이 비활성이 되면 되돌리고, 다시 활성이면 그때 밝기를 기억하고 올린다")
  func inactiveRestoresAndActiveRaisesAgain() {
    let screen = FakeScreen(brightness: 0.4)
    let booster = Self.raisedBooster(on: screen)

    booster.sceneActivityChanged(false)
    #expect(screen.brightness == 0.4)

    // 앱 밖에서 사용자가 밝기를 바꿨다.
    screen.brightness = 0.7
    booster.sceneActivityChanged(true)
    #expect(screen.brightness == 1)
    #expect(booster.raised?.savedBrightness == 0.7)

    booster.visibilityChanged(false)
    #expect(screen.brightness == 0.7)
  }

  @Test("다른 화면으로 옮겨 가면 앞 화면을 되돌리고 새 화면을 올린다")
  func movingToAnotherScreenRestoresPrevious() {
    let first = FakeScreen(brightness: 0.4)
    let second = FakeScreen(brightness: 0.6)
    let booster = Self.raisedBooster(on: first)

    booster.screenChanged(second)

    #expect(first.brightness == 0.4)
    #expect(second.brightness == 1)
    #expect(booster.raised?.screen === second)
    #expect(booster.raised?.savedBrightness == 0.6)
  }

  @Test("이미 올린 같은 화면에 신호가 다시 와도 다시 기억하지 않는다")
  func repeatedSignalsDoNotResave() {
    let screen = FakeScreen(brightness: 0.4)
    let booster = Self.raisedBooster(on: screen)

    booster.screenChanged(screen)
    booster.visibilityChanged(true)
    booster.sceneActivityChanged(true)

    #expect(booster.raised?.savedBrightness == 0.4)
    #expect(screen.writes == [1])
  }

  @Test("보이지 않을 때 화면이 와도 올리지 않는다")
  func screenWhileHiddenDoesNotRaise() {
    let screen = FakeScreen(brightness: 0.4)
    let booster = BrightnessBooster<FakeScreen>()

    booster.sceneActivityChanged(true)
    booster.screenChanged(screen)

    #expect(screen.brightness == 0.4)
    #expect(screen.writes.isEmpty)
    #expect(booster.raised == nil)
  }

  @Test("올려 둔 채 해제되면 되돌린다")
  func releaseRestoresRaisedScreen() {
    let screen = FakeScreen(brightness: 0.4)
    do {
      let booster = Self.raisedBooster(on: screen)
      #expect(screen.brightness == 1)
      _ = booster
    }

    #expect(screen.brightness == 0.4)
  }

  @Test("올리지 않은 채 해제되면 밝기를 건드리지 않는다")
  func releaseWithoutRaisingLeavesBrightness() {
    let screen = FakeScreen(brightness: 0.4)
    do {
      let booster = BrightnessBooster<FakeScreen>()
      booster.screenChanged(screen)
    }

    #expect(screen.writes.isEmpty)
  }

  /// 보이고 활성이며 `screen` 에 올린 booster.
  static func raisedBooster(on screen: FakeScreen) -> BrightnessBooster<FakeScreen> {
    let booster = BrightnessBooster<FakeScreen>()
    booster.screenChanged(screen)
    booster.visibilityChanged(true)
    booster.sceneActivityChanged(true)
    return booster
  }
}

/// 밝기 쓰기를 기록하는 가짜 화면.
@MainActor
final class FakeScreen: BrightnessAdjustable {
  /// 쓴 값을 차례로(테스트가 직접 쓴 값 포함).
  private(set) var writes: [CGFloat] = []
  private var value: CGFloat

  init(brightness: CGFloat) {
    self.value = brightness
  }

  var brightness: CGFloat {
    get { self.value }
    set {
      self.value = newValue
      self.writes.append(newValue)
    }
  }
}
