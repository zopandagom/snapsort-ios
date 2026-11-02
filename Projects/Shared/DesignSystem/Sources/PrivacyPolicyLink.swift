import SwiftUI

/// 개인정보 처리방침 웹 페이지(`site/privacy/index.html` 을 GitHub Pages 로 게시)를 기본 브라우저로 여는 링크.
/// 누를 때만 열고 앱은 아무 데이터도 보내지 않는다(ARCHITECTURE §4 개인정보 처리방침 행).
/// 앱 안에 처리방침 링크를 두라는 심사 가이드라인 5.1.1(i) 때문에 온보딩(소개·거부·제한 화면)과 보관함 맨 아래에 둔다.
public struct PrivacyPolicyLink: View {
  /// 처리방침 주소. `.github/workflows/pages.yml` 이 게시하는 경로와 같아야 한다.
  public static let url = URL(string: "https://zopandagom.github.io/snapsort-ios/privacy/")

  public init() {}

  public var body: some View {
    // 상수 문자열이라 nil 이 되지 않지만 강제 언래핑하지 않는다(CONVENTIONS §2).
    if let url = Self.url {
      Link(destination: url) {
        Label("개인정보 처리방침", systemImage: "arrow.up.right")
          .labelStyle(.titleAndTrailingIcon)
      }
      .font(.footnote)
      // 루트 `snapTheme()` 의 글자색을 물려받지 않고 링크로 보이게 tint 로 그린다.
      .foregroundStyle(.tint)
    }
  }
}

private struct TitleAndTrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 2) {
      configuration.title
      configuration.icon
        .imageScale(.small)
        // 바깥으로 나가는 표시일 뿐이라 VoiceOver 에서는 제목만 읽는다.
        .accessibilityHidden(true)
    }
  }
}

private extension LabelStyle where Self == TitleAndTrailingIconLabelStyle {
  static var titleAndTrailingIcon: TitleAndTrailingIconLabelStyle { TitleAndTrailingIconLabelStyle() }
}
