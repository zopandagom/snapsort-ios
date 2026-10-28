import Core
import DesignSystem
import SwiftUI

/// 보관함 화면의 카테고리 카드: 대표 사진 모자이크 + 아이콘 칸 + 이름 + 개수. 누르면 그 카테고리 화면을 연다.
/// 카드 하나가 접근성 요소 하나("기프티콘, 24장")이고 모자이크·아이콘은 장식이다.
/// 대표 썸네일은 `LibraryCoverModel` 이 대표가 바뀔 때 읽어 두므로, 카드가 보일 때는 대체 표시 칸의 다시 시도만 요청한다.
struct LibraryCategoryCard: View {
  /// 이름 줄 수. 큰 글씨에서 이름이 잘리지 않게 2열 격자는 `.xLarge` 이상에서 두 줄 자리를 잡고, 1열은 제한하지 않는다.
  enum TitleLines {
    case single
    case double
    case unlimited
  }

  let category: ImageCategory
  let count: Int
  let ids: [ImageAsset.ID]
  let coverModel: LibraryCoverModel
  /// 가로로 넓은 모자이크(여행 카드, 1열 격자).
  let isWide: Bool
  let titleLines: TitleLines

  @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 32

  var body: some View {
    NavigationLink(value: self.category) {
      VStack(alignment: .leading, spacing: 10) {
        CoverMosaic(self.tiles, fallback: self.category.glyph, aspectRatio: self.isWide ? 2.5 : 4 / 3)
        HStack(spacing: 8) {
          IconTile(self.category.glyph, size: self.iconSize, scale: .compact)
          VStack(alignment: .leading, spacing: 0) {
            self.titleText
            Text(self.category.countText(self.count))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(self.titleLines == .unlimited ? nil : 1)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
      }
      .snapCard(padding: 8)
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .accessibilityElement(children: .ignore)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(self.category.title), \(self.category.countText(self.count))")
    .onAppear { self.coverModel.cardAppeared(ids: self.ids) }
  }

  @ViewBuilder
  private var titleText: some View {
    let title = Text(self.category.title).font(.subheadline.bold())
    switch self.titleLines {
    case .single:
      title.lineLimit(1)
    case .double:
      title.lineLimit(2, reservesSpace: true)
    case .unlimited:
      title
    }
  }

  /// 대표가 없으면 빈 배열이라 모자이크가 아이콘 한 칸을 보인다.
  private var tiles: [CoverMosaic.Tile] {
    self.ids.map { id in
      switch self.coverModel.thumbnails[id] {
      case let .loaded(image):
        .image(image.cgImage, orientation: image.orientation)
      case .unavailable:
        .glyph
      case .loading, nil:
        .pending
      }
    }
  }
}
