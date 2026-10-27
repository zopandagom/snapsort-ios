import SwiftUI

/// 알약형 버튼. 채운 버튼(`.snapPrimary`)은 강조색 바탕에 `onAccent` 글자, 보조 버튼(`.snapSecondary`)은 블러시 바탕에 강조색 글자다.
/// 시스템 `.borderedProminent` 는 다크에서 밝은 로즈 위에 흰 글자(대비 2.47)를, `.bordered` 는 라이트에서 옅은 바탕 위 강조색(약 4.4)을 그려 대신 쓴다.
/// `role: .destructive` 는 경고색(`SnapColor.danger`)으로 그린다. 크기는 `controlSize` 를 따르고, 글자 크기는 바깥 `.font` 를 따른다(`.large` 만
/// headline).
public struct SnapButtonStyle: ButtonStyle {
  public enum Kind: Sendable {
    case primary
    case secondary
  }

  private let kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public func makeBody(configuration: Configuration) -> some View {
    PillButton(kind: self.kind, configuration: configuration)
  }
}

public extension ButtonStyle where Self == SnapButtonStyle {
  static var snapPrimary: SnapButtonStyle { SnapButtonStyle(.primary) }
  static var snapSecondary: SnapButtonStyle { SnapButtonStyle(.secondary) }
}

private struct PillButton: View {
  let kind: SnapButtonStyle.Kind
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize

  var body: some View {
    self.sized(self.configuration.label)
      .fontWeight(.semibold)
      .multilineTextAlignment(.center)
      .foregroundStyle(self.foreground)
      .background(self.fill, in: .capsule)
      .contentShape(.capsule)
      .opacity(self.configuration.isPressed ? 0.75 : 1)
  }

  @ViewBuilder
  private func sized(_ label: some View) -> some View {
    switch self.controlSize {
    case .mini, .small:
      label.padding(.vertical, 6).padding(.horizontal, 12)
    case .large, .extraLarge:
      label.font(.headline).padding(.vertical, 13).padding(.horizontal, 22).frame(minHeight: 48)
    default:
      label.padding(.vertical, 9).padding(.horizontal, 16).frame(minHeight: 36)
    }
  }

  /// `role: .destructive` 는 강조색 대신 경고색을 써서 옆의 보통 버튼과 구분한다.
  private var isDestructive: Bool {
    self.configuration.role == .destructive
  }

  private var foreground: ColorToken {
    guard self.isEnabled else { return SnapColor.inkSecondary }
    switch self.kind {
    case .primary: return SnapColor.onAccent
    case .secondary: return self.isDestructive ? SnapColor.danger : SnapColor.accent
    }
  }

  private var fill: ColorToken {
    guard self.isEnabled else { return SnapColor.neutral }
    switch self.kind {
    case .primary: return self.isDestructive ? SnapColor.danger : SnapColor.accent
    case .secondary: return self.isDestructive ? SnapColor.dangerSoft : SnapColor.blush
    }
  }
}
