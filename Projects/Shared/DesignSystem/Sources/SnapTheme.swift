import SwiftUI
import UIKit

public extension View {
  /// 화면 루트에 한 번 붙인다: rounded 글꼴, 강조색, 본문·보조 글자색. 하위의 `.secondary` 는 `SnapColor.inkSecondary` 가 된다.
  /// 본문 글자색이 버튼 tint 를 덮으므로 색을 정하지 않은 글자 버튼과 툴바 `Menu` 라벨에는 `.foregroundStyle(.tint)` 를 준다
  /// (툴바 Menu 는 물려받은 글자색을 흰색으로 그린다).
  func snapTheme() -> some View {
    self
      .fontDesign(.rounded)
      .tint(SnapColor.accent)
      .foregroundStyle(SnapColor.ink, SnapColor.inkSecondary)
  }

  /// 화면(내비게이션 컨테이너) 바탕을 `SnapColor.background` 로 바꾼다. push 되는 화면마다 루트에 붙여, 불러오는 중·실패 상태도 같은 바탕이 되게 한다.
  /// 안쪽 List 의 시스템 바탕도 숨긴다. List 칸 색은 `SnapList` 가 정한다.
  func snapScreenBackground() -> some View {
    self
      .scrollContentBackground(.hidden)
      .containerBackground(SnapColor.background, for: .navigation)
  }
}

/// 칸이 `SnapColor.card` 인 List. 바탕은 화면의 `snapScreenBackground()` 가 정한다. 칸이 직접 정한 `listRowBackground` 가 이긴다.
public struct SnapList<Content: View>: View {
  private let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    List {
      Group {
        self.content
      }
      .listRowBackground(Rectangle().fill(SnapColor.card))
    }
    .scrollContentBackground(.hidden)
  }
}

/// 내비게이션 바 제목의 rounded 굵은 글꼴과 `SnapColor.ink` 글자색. SwiftUI `.fontDesign`·`.foregroundStyle` 이 닿지 않는 UIKit 바라 appearance
/// 로 정한다.
/// SF Pro Rounded 에는 한글 글리프가 없어 한글 제목은 시스템 한글 글꼴로 그려진다(굵기만 따른다).
public enum SnapNavigationBar {
  /// 앱 시작 때 한 번 부른다. 글자 크기는 부를 때의 Dynamic Type 값이라, 실행 중 크기를 바꾸면 다음 실행부터 반영된다.
  @MainActor
  public static func applyRoundedTitles() {
    let bar = UINavigationBar.appearance()
    let ink = UIColor(SnapColor.ink)
    bar.largeTitleTextAttributes = [.font: self.roundedFont(.largeTitle, weight: .heavy), .foregroundColor: ink]
    bar.titleTextAttributes = [.font: self.roundedFont(.headline, weight: .semibold), .foregroundColor: ink]
  }

  private static func roundedFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let base = UIFont.preferredFont(forTextStyle: style)
    let weighted = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    let descriptor = weighted.withDesign(.rounded) ?? weighted
    return UIFont(descriptor: descriptor, size: base.pointSize)
  }
}

extension UIColor {
  /// 색 모드에 따라 라이트·다크 값을 고르는 UIKit 색. UIKit appearance 처럼 `ShapeStyle` 을 받지 않는 곳에 쓴다.
  convenience init(_ token: ColorToken) {
    self.init { traits in
      let hex = traits.userInterfaceStyle == .dark ? token.dark : token.light
      return UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
    }
  }
}
