import ImageIO
import SwiftUI

/// 격자의 정사각형 썸네일 칸. 이미지는 칸을 채우도록 늘린 뒤 잘라 낸다.
public struct ThumbnailTile: View {
  public enum Content {
    /// 회색 바탕에 작은 진행 표시.
    case loading
    /// 회전하지 않은 픽셀과 바르게 보이는 방향 (Core `AnalysisImage` 의 두 값).
    case image(CGImage, orientation: CGImagePropertyOrientation)
    /// 회색 바탕에 심볼. 읽지 못한 이미지의 대체 표시다.
    case placeholder(systemImage: String)
  }

  private let content: Content
  private let accessibilityLabel: Text

  public init(_ content: Content, accessibilityLabel: Text) {
    self.content = content
    self.accessibilityLabel = accessibilityLabel
  }

  public var body: some View {
    Color(.secondarySystemFill)
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        switch self.content {
        case .loading:
          ProgressView()
            .controlSize(.small)
        case let .image(cgImage, orientation):
          Image(decorative: cgImage, orientation: orientation)
            .resizable()
            .scaledToFill()
        case let .placeholder(systemImage):
          Image(systemName: systemImage)
            .foregroundStyle(.secondary)
        }
      }
      .clipped()
      // `.clipped()` 는 그리기만 자른다. 칸 밖으로 넘친 scaledToFill 이미지가 옆 칸의 터치·접근성 영역을 덮지 않게 칸 모양으로 한정한다.
      .contentShape([.interaction, .accessibility], Rectangle())
      .accessibilityElement()
      .accessibilityLabel(self.accessibilityLabel)
  }
}
