import Core
import DesignSystem
import SwiftUI

/// 보관함 화면의 카테고리 카드: 대표 사진 모자이크 + 아이콘 칸 + 이름 + 개수. 누르면 그 카테고리 화면을 연다.
/// 누르면 작아졌다 돌아오고(`.snapCard` 버튼 스타일), 카테고리 화면은 이 카드에서 커지며 열린다(`LibraryView` 의 줌 전환).
/// 카드 하나가 접근성 요소 하나("기프티콘, 24장")이고 모자이크·아이콘은 장식이다.
/// 대표 썸네일은 `LibraryCoverModel` 이 대표가 바뀔 때 읽어 두므로, 카드가 보일 때는 대체 표시 칸의 다시 시도만 요청한다.
/// 대표 칸의 종류(빈 칸·사진·아이콘)가 바뀌면(사진이 처음 읽혀 들어올 때 등) 그 칸만 흐림에서 또렷하게 바뀐다(`CoverMosaic`, 동작 줄이기면 투명도).
/// 화면에 처음 생길 때의 순서 등장은 격자(`LibraryView+Grid.swift`)가 카드 밖에서 건다.
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
  /// 카테고리 화면으로 줌 전환할 때 이 카드를 출발점으로 삼는 이름 공간(`LibraryView.zoomNamespace`).
  let zoomNamespace: Namespace.ID

  @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 32

  var body: some View {
    NavigationLink(value: self.category) {
      VStack(alignment: .leading, spacing: 10) {
        CoverMosaic(self.tiles, fallback: self.category.glyph, aspectRatio: self.isWide ? 2.5 : 4 / 3)
        HStack(spacing: 8) {
          IconTile(self.category.glyph, size: self.iconSize, scale: .compact)
          VStack(alignment: .leading, spacing: 0) {
            self.titleText
            // 분류 중 개수가 늘면 바뀐 자리만 굴러간다(동작 줄이기면 바로 바뀐다).
            Text.snapNumbered(self.category.countText(self.count), style: .caption)
              .foregroundStyle(.secondary)
              .lineLimit(self.titleLines == .unlimited ? nil : 1)
              .snapRollingNumber(self.count)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
      }
      .snapCard(padding: 8)
      .accessibilityElement(children: .ignore)
    }
    .buttonStyle(.snapCard)
    .matchedTransitionSource(id: self.category, in: self.zoomNamespace) { source in
      source.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .accessibilityLabel("\(self.category.title), \(self.category.countText(self.count))")
    .onAppear { self.coverModel.cardAppeared(ids: self.ids) }
  }

  @ViewBuilder
  private var titleText: some View {
    let title = Text(self.category.title).font(.snap(.subheadline, weight: .bold))
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
