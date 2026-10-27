import SwiftUI

/// 빈 화면·불러오기 실패 안내. `ContentUnavailableView` 에 선택적 다시 시도 버튼을 붙인다.
/// 상태 아이콘은 SF Symbols, 카테고리 빈 화면은 카테고리 아이콘(`SnapGlyph`)을 쓴다.
public struct StatusMessageView: View {
  private enum Icon {
    case symbol(String)
    case glyph(SnapGlyph)
  }

  private let title: String
  private let icon: Icon
  private let description: String?
  private let retry: (() -> Void)?

  /// - Parameter retry: 정하면 "다시 시도" 버튼을 보이고 누를 때 부른다.
  public init(_ title: String, systemImage: String, description: String? = nil, retry: (() -> Void)? = nil) {
    self.title = title
    self.icon = .symbol(systemImage)
    self.description = description
    self.retry = retry
  }

  /// 카테고리 빈 화면. 아이콘을 색 칸에 그린다.
  public init(_ title: String, glyph: SnapGlyph, description: String? = nil, retry: (() -> Void)? = nil) {
    self.title = title
    self.icon = .glyph(glyph)
    self.description = description
    self.retry = retry
  }

  public var body: some View {
    ContentUnavailableView {
      // 제목이 상태를 말하므로 심볼은 VoiceOver 에서 읽지 않는다.
      Label {
        Text(self.title)
      } icon: {
        switch self.icon {
        case let .symbol(name):
          Image(systemName: name)
        case let .glyph(glyph):
          GlyphHeaderIcon(glyph: glyph)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(self.title))
    } description: {
      if let description = self.description {
        Text(description)
      }
    } actions: {
      if let retry = self.retry {
        Button("다시 시도", action: retry)
          .buttonStyle(.snapSecondary)
      }
    }
  }
}

/// 빈 화면 제목 위의 카테고리 아이콘. 큰 글씨를 따라 커진다.
private struct GlyphHeaderIcon: View {
  let glyph: SnapGlyph

  @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

  var body: some View {
    IconTile(self.glyph, size: self.size)
  }
}
