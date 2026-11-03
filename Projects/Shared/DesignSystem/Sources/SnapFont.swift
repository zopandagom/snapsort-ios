import SwiftUI
import UIKit

/// 앱 글자 전체에 쓰는 둥근 한글 글꼴(나눔스퀘어라운드 R·B·EB, SIL OFL 1.1, `Resources/Fonts/OFL.txt`).
/// SF Pro Rounded 에는 한글 글리프가 없어 한글이 각진 시스템 글꼴로 나오던 것을 맞춘다. 기본 본문 글꼴은 `snapTheme()` 가 R 로 정하고,
/// 크기·굵기를 정하는 곳은 `Font.snap(_:weight:)` 를 쓴다. 시스템이 그리는 알림창·확인 대화상자·메뉴·알림 글자는 바뀌지 않는다.
/// 이 글꼴에는 고정폭 숫자(tnum)가 없어, 굴러가는 수·D-n·금액·순번·큰 개수는 시스템 rounded 고정폭 숫자(`Font.snapNumber`·
/// `Text.snapNumbered`, SnapNumberText.swift)로 그린다. 바코드 번호처럼 사람이 옮겨 적는 코드는 0/O·1/l 구분을 위해 시스템 monospaced 다.
///
/// 손쉬운 사용 '굵은 텍스트'는 사용자 지정 글꼴에 자동으로 적용되지 않아(시스템 글꼴만 굵어진다) 켜져 있으면 한 단계 굵은 글꼴을 고른다.
/// 글꼴을 만들 때 읽으므로 설정을 바꾸면 다시 그려지는 화면부터 반영된다.
///
/// 글꼴 파일은 이 모듈의 리소스 번들에 있고, 이름·등록 코드는 Tuist 가 만든 `DesignSystemFontFamily` 다. `Font.snap`·
/// `SnapNavigationBar` 가 처음 쓰일 때 프로세스 범위로 한 번 등록하므로 앱·위젯·Example 진입점에서 따로 부를 것이 없다
/// (위젯 Extension 은 Info.plist `UIAppFonts` 로도 등록된다, Tuist `Env.designSystemFontPaths`).
/// 글꼴 등록이 실패하면 `Font.custom` 이 같은 크기의 시스템 글꼴로, `uiFont` 는 시스템 글꼴로 그린다. 리소스 번들이 없는 제품에서는
/// Tuist 가 만든 `Bundle.module` 이 멈추므로, DesignSystem 을 쓰는 새 타깃은 Tuist 의존성으로 연결해 번들이 담기게 한다.
public enum SnapFont {
  /// 굵기는 자리(역할)로 고른다: 시스템 글꼴 때의 굵기보다 역할이 우선이다(예: 시스템 `.title2.bold()` 였던 화면 큰 제목도 EB).
  public enum Weight: Sendable, CaseIterable {
    /// 본문·설명·보조 글자.
    case regular
    /// 작은 제목·섹션 머리말·카드 이름·버튼·배지·진행 막대 라벨과 값·내비게이션 바 작은 제목. 시스템 `.headline` 자리도 B 다.
    case bold
    /// 화면 큰 제목·섹션 큰 제목·큰 숫자·도장·내비게이션 바 큰 제목.
    case extraBold

    /// '굵은 텍스트'가 켜져 있으면 한 단계 굵게.
    public func resolved(boldText: Bool) -> Self {
      guard boldText else { return self }
      switch self {
      case .regular: return .bold
      case .bold, .extraBold: return .extraBold
      }
    }

    /// 등록된 글꼴의 PostScript 이름.
    var postScriptName: String {
      switch self {
      case .regular: DesignSystemFontFamily.NanumSquareRoundOTF.regular.name
      case .bold: DesignSystemFontFamily.NanumSquareRoundOTF.bold.name
      case .extraBold: DesignSystemFontFamily.NanumSquareRoundOTF.extraBold.name
      }
    }
  }

  /// 손쉬운 사용 '굵은 텍스트'. `UIAccessibility.isBoldTextEnabled` 와 같은 값을, 메인 액터 밖(위젯 타임라인·nonisolated 뷰 조각)에서도
  /// 읽히도록 시스템 본문 글꼴의 굵기로 읽는다(켜면 시스템 본문이 regular 보다 굵어진다).
  static var isBoldTextEnabled: Bool {
    let traits = UIFont.preferredFont(forTextStyle: .body).fontDescriptor
      .object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
    let weight = (traits?[.weight] as? CGFloat) ?? UIFont.Weight.regular.rawValue
    return weight > UIFont.Weight.regular.rawValue
  }

  /// 여러 번 불러도 한 번만 등록한다(static let 초기화는 스레드 안전).
  static func registerIfNeeded() {
    _ = self.registration
  }

  private static let registration: Void = DesignSystemFontFamily.registerAllCustomFonts()

  /// Dynamic Type 기본(Large) 크기. `Font.custom(_:size:relativeTo:)` 가 여기서부터 키운다.
  static func baseSize(_ style: Font.TextStyle) -> CGFloat {
    self.baseSizes[style] ?? 17
  }

  private static let baseSizes: [Font.TextStyle: CGFloat] = [
    .largeTitle: 34, .title: 28, .title2: 22, .title3: 20, .headline: 17, .body: 17,
    .callout: 16, .subheadline: 15, .footnote: 13, .caption: 12, .caption2: 11,
  ]

  /// UIKit(내비게이션 바)용. 글자 크기는 부를 때의 Dynamic Type 값이다.
  static func uiFont(_ style: UIFont.TextStyle, weight: Weight) -> UIFont {
    self.registerIfNeeded()
    let base = UIFont.preferredFont(forTextStyle: style)
    return UIFont(name: weight.resolved(boldText: SnapFont.isBoldTextEnabled).postScriptName, size: base.pointSize) ??
      base
  }
}

public extension Font {
  /// 둥근 한글 글꼴. `style` 의 Dynamic Type 을 따른다. 굵기는 `weight` 로 정한다. 덧붙인 `.fontWeight`·`.bold()` 도 같은 글꼴 묶음에서
  /// 고르므로(semibold·bold → B, heavy·black → EB) 버튼 스타일처럼 크기를 바깥에서 받는 곳은 굵기만 덧붙여도 된다.
  static func snap(_ style: Font.TextStyle, weight: SnapFont.Weight = .regular) -> Font {
    SnapFont.registerIfNeeded()
    return .custom(
      weight.resolved(boldText: SnapFont.isBoldTextEnabled).postScriptName,
      size: SnapFont.baseSize(style),
      relativeTo: style
    )
  }

  /// 크기를 직접 정한 곳(위젯의 큰 숫자·작은 원형 위젯 글자)의 고정 크기 판. Dynamic Type 을 따르지 않는다.
  static func snap(fixedSize size: CGFloat, weight: SnapFont.Weight = .regular) -> Font {
    SnapFont.registerIfNeeded()
    return .custom(weight.resolved(boldText: SnapFont.isBoldTextEnabled).postScriptName, fixedSize: size)
  }
}
