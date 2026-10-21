import SwiftUI
import UIKit

extension View {
  /// 이 화면이 보이고 앱이 앞에 있는 동안 화면 밝기를 최대로 두고, 그 밖에는 원래 밝기로 되돌린다
  /// (docs/ARCHITECTURE.md §1 규칙 8: 화면에만 걸린 시스템 UI 설정은 View 가 맡고 떠나면 되돌린다).
  func screenBrightnessMaximized() -> some View {
    self.modifier(ScreenBrightnessModifier())
  }
}

/// View 의 신호(보임·앱 활성·붙은 창의 화면)를 `BrightnessBooster` 에 넘긴다. 판단과 되돌리기는 booster 가 한다.
/// 화면은 `UIScreen.main`(iOS 26 deprecated) 대신 이 View 가 붙은 창의 화면을 쓴다.
private struct ScreenBrightnessModifier: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  @State private var booster = BrightnessBooster<UIScreen>()

  func body(content: Content) -> some View {
    content
      .background {
        WindowScreenReader { self.booster.screenChanged($0) }
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
      }
      .onAppear {
        self.booster.visibilityChanged(true)
        self.booster.sceneActivityChanged(self.scenePhase == .active)
      }
      .onDisappear {
        self.booster.visibilityChanged(false)
      }
      .onChange(of: self.scenePhase) { _, phase in
        self.booster.sceneActivityChanged(phase == .active)
      }
  }
}

/// 밝기를 바꿀 수 있는 화면. `UIScreen` 이 따르고, 테스트는 가짜 class 를 쓴다.
@MainActor
protocol BrightnessAdjustable: AnyObject {
  var brightness: CGFloat { get set }
}

extension UIScreen: BrightnessAdjustable {}

/// 바코드 크게 보기의 밝기 올림·되돌림 판단과 실행. 화면 하나의 수명 동안 View 가 `@State` 로 하나 갖는다(관찰하지 않는 참조).
/// Model 이 아니다: 관찰하지 않고 비즈니스 의미가 없는, 화면에만 걸린 시스템 UI 설정(ARCHITECTURE §1 규칙 8)의 실행 도우미라
/// 규칙 7(Model 은 App 이 소유)의 대상이 아니다.
/// 올린 화면과 올리기 전 밝기를 기억했다가 그 화면에 되돌리므로, 닫을 때 화면 신호(nil)·사라짐·해제 중 어느 것이 먼저 오든 한 번만 되돌린다.
/// - 보이고 앱이 활성이고 화면을 알면: 그때 밝기를 기억하고 최대로. 이미 같은 화면에 올렸으면 다시 기억하지 않는다.
/// - 사라지거나 앱이 비활성·뒤로 가거나(제어 센터·앱 전환·잠금) 화면이 바뀌거나 없어지면: 올린 화면에 기억한 밝기를 되돌린다.
///   다시 활성이 되면 그때 밝기(사용자가 바꾼 값)를 다시 기억하고 올린다. 다른 화면으로 옮겨 가면 앞 화면을 되돌리고 새 화면을 올린다.
/// - 앱이 강제 종료되면 되돌리지 못한다(iOS 가 되돌리는지는 실기기에서 확인한다).
@MainActor
final class BrightnessBooster<Screen: BrightnessAdjustable> {
  /// 올린 화면과 올리기 전 밝기. nil 이면 올리지 않았다. 되돌릴 때는 지금 알려진 화면이 아니라 이 화면에 되돌린다.
  private(set) var raised: (screen: Screen, savedBrightness: CGFloat)?
  private var isVisible = false
  private var isActive = false
  private var screen: Screen?

  init() {}

  /// 보이기 시작했다(onAppear, true) / 사라졌다(onDisappear, false).
  func visibilityChanged(_ isVisible: Bool) {
    self.isVisible = isVisible
    self.apply()
  }

  /// 앱이 활성인지(처음 값과 scenePhase 변화).
  func sceneActivityChanged(_ isActive: Bool) {
    self.isActive = isActive
    self.apply()
  }

  /// 붙은 창의 화면. 창에서 떨어지면 nil.
  func screenChanged(_ screen: Screen?) {
    self.screen = screen
    self.apply()
  }

  /// 1) 올린 화면이 있고 보이지 않거나 비활성이거나 지금 화면이 그 화면이 아니면(nil 포함) 올린 화면에 기억한 밝기를 되돌린다.
  /// 2) 보이고 활성이고 지금 화면이 있고 올린 화면이 없으면 그 화면의 지금 밝기를 기억하고 최대로 올린다.
  /// 3) 이미 같은 화면에 올려 있으면 아무것도 하지 않는다.
  private func apply() {
    if let raised = self.raised, !self.isVisible || !self.isActive || self.screen !== raised.screen {
      raised.screen.brightness = raised.savedBrightness
      self.raised = nil
    }
    if self.isVisible, self.isActive, let screen = self.screen, self.raised == nil {
      self.raised = (screen, screen.brightness)
      screen.brightness = 1
    }
  }

  /// 마지막 안전망: View 가 사라짐 신호 없이 사라져 이 객체가 해제되면 되돌린다. 올리지 않았으면 아무것도 하지 않는다.
  isolated deinit {
    if let raised = self.raised {
      raised.screen.brightness = raised.savedBrightness
    }
  }
}

/// 붙은 창의 화면을 알려 준다. 창에 붙거나 떨어질 때마다 부른다(떨어지면 nil).
private struct WindowScreenReader: UIViewRepresentable {
  let onScreen: (UIScreen?) -> Void

  func makeUIView(context _: Context) -> ReaderView {
    let view = ReaderView()
    view.onScreen = self.onScreen
    return view
  }

  func updateUIView(_ view: ReaderView, context _: Context) {
    view.onScreen = self.onScreen
  }

  final class ReaderView: UIView {
    var onScreen: ((UIScreen?) -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      self.onScreen?(self.window?.windowScene?.screen)
    }
  }
}
