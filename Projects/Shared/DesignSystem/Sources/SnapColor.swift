import SwiftUI

/// 라이트·다크 한 쌍의 sRGB 값(0xRRGGBB). 그릴 때 환경의 색 모드로 고르므로 `ShapeStyle` 자리에 그대로 쓴다.
public struct ColorToken: ShapeStyle, Hashable {
  public let light: UInt32
  public let dark: UInt32

  public init(light: UInt32, dark: UInt32) {
    self.light = light
    self.dark = dark
  }

  public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    let hex = environment.colorScheme == .dark ? self.dark : self.light
    return Color.Resolved(
      red: Float((hex >> 16) & 0xFF) / 255,
      green: Float((hex >> 8) & 0xFF) / 255,
      blue: Float(hex & 0xFF) / 255
    )
  }
}

/// 앱 색 기준값 (소프트 로즈). 글자로 쓰는 조합은 라이트·다크 모두 대비 4.5:1 이상이다(`SnapColorTests`).
/// 로즈는 두 단계다: 면·아이콘은 `rose`, 글자·강조색·채운 버튼은 한 단계 진한 `accent`.
public enum SnapColor {
  /// 강조색. 글자·선택 표시·채운 버튼 바탕. App 의 `AccentColor` 에셋과 같은 값이다.
  public static let accent = ColorToken(light: 0xC42854, dark: 0xFF7A9C)
  /// `accent` 위의 글자.
  public static let onAccent = ColorToken(light: 0xFFFFFF, dark: 0x1C1719)
  /// 면·아이콘용 로즈. 글자에는 쓰지 않는다(바탕 위 대비 3.96).
  public static let rose = ColorToken(light: 0xD9466F, dark: 0xFF7A9C)
  /// 강조 면. 보조 버튼·배지 바탕.
  public static let blush = ColorToken(light: 0xFFE1EA, dark: 0x4A2230)
  /// 보조색. 진행 표시 같은 면에만 쓴다. 글자는 `lilacText`.
  public static let lilac = ColorToken(light: 0x8B7CF6, dark: 0xA99CFF)
  public static let lilacText = ColorToken(light: 0x5B3FC4, dark: 0xC4BAFF)
  public static let lilacSoft = ColorToken(light: 0xECE6FF, dark: 0x3A3060)
  /// 포인트. 반짝임 같은 장식에만 쓴다(글자 대비가 낮다).
  public static let butter = ColorToken(light: 0xFFC857, dark: 0xFFD47A)
  /// 화면 바탕.
  public static let background = ColorToken(light: 0xFFF8F5, dark: 0x1C1719)
  /// 카드·목록 칸.
  public static let card = ColorToken(light: 0xFFFFFF, dark: 0x2A2327)
  /// 경고 글자. 삭제처럼 되돌리기 어려운 버튼(`role: .destructive`)에 쓴다.
  public static let danger = ColorToken(light: 0xB3261E, dark: 0xFF8A80)
  /// 경고 면.
  public static let dangerSoft = ColorToken(light: 0xFDE4E1, dark: 0x4A1F1C)
  /// 지난 항목 배지 같은 중립 면.
  public static let neutral = ColorToken(light: 0xF1ECEE, dark: 0x3A3236)
  /// 본문 글자.
  public static let ink = ColorToken(light: 0x2A2226, dark: 0xF5EDF0)
  /// 보조 글자. 시스템 `.secondary` 자리를 `snapTheme()` 가 이 값으로 바꾼다.
  public static let inkSecondary = ColorToken(light: 0x6B5D63, dark: 0xB9AAB0)
}
