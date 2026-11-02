import Core
import DesignSystem
import SwiftUI

// MARK: - 곧 만료 띠

extension LibraryView {
  /// 띠를 보일지. 첫 읽기 전·처음부터 실패·저장소 없음(nil)이거나 창 안 기프티콘이 0개면 숨긴다.
  /// `homeGrid` 의 등장 애니메이션 값이다(숨김 ↔ 보임이 바뀔 때만 전환이 돈다).
  var showsExpiringStrip: Bool {
    guard let strip = self.model.expiringGifticons else { return false }
    return !strip.isEmpty
  }

  /// 띠가 나타나고 사라지는 전환. 위에서 내려오며 나타나고 같은 길로 접힌다. 동작 줄이기면 투명도만.
  var expiringStripTransition: AnyTransition {
    self.reduceMotion ? .opacity : AnyTransition.offset(y: -12).combined(with: .opacity)
  }

  /// 띠가 나타나고 사라질 때 아래 카드들이 함께 움직이는 애니메이션. 동작 줄이기면 투명도 전환 시간만 쓴다.
  var expiringStripAnimation: Animation {
    self.reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.15)
  }
}

/// 위젯 오늘 요약과 같은 집합(오늘 ~ 오늘 + `ExpiryWidgetTimeline.windowDays`, 미사용, 지금 규칙 버전으로 추출한 만료일)의 가로 띠.
/// 머리("곧 만료되는 기프티콘 n개" + "모두 보기")와 칩(썸네일 · 그 위 D-n 배지 · 아래 교환처). 칩은 Model 상한(`LibraryModel.expiringLimit`)까지만
/// 두고, 넘는 몫은 끝의 "+k" 칩이 기프티콘 목록으로 보낸다.
/// 칩을 누르면 띠에 보이던 칩 전부를 한 섹션으로 실어 사진 상세를 연다(기프티콘 목록에서 연 것처럼 기프티콘 정보·사용함·바코드).
/// 칩 썸네일에서 커지며 열리고 닫을 때 지금 장의 칩으로 줄어드는 줌 전환이다(`photoZoomSource`. 그 사이 칩이 띠에서 빠졌으면 출발점이 없다).
/// 상세에서 돌아와 다시 보일 때 이 방문(`visit`)의 돌아올 위치가 있으면 그 칩이 보이게 한 번 가로로 스크롤한다(`CategoryModel.detailReturn`).
/// 칩 썸네일은 `LibraryCoverModel` 이 띠 칩 집합으로 읽어 둔다(`LibraryView` 의 `expiringThumbnailIDs` 신호). 카드처럼 보일 때는 대체 칸의 다시 시도만
/// 요청한다.
struct LibraryExpiringStripView: View {
  let strip: ExpiringGifticons
  let coverModel: LibraryCoverModel
  let categoryModel: CategoryModel
  /// 돌아올 위치를 가를 방문 값. Lazy 재생성에 잃지 않게 `LibraryView` 가 갖는다(`LibraryView.expiringVisit`).
  let visit: UUID

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// 칩 썸네일 한 변. 큰 글씨를 따라 커지되 `maxSide` 를 넘지 않는다.
  @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 76
  private static let maxSide: CGFloat = 132

  private var side: CGFloat {
    min(self.scaledSide, Self.maxSide)
  }

  private var isAccessibilitySize: Bool {
    self.dynamicTypeSize.isAccessibilitySize
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      self.header
      self.chips
    }
  }

  // MARK: 머리

  @ViewBuilder
  private var header: some View {
    if self.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 6) {
        self.title
        self.allLink
      }
    } else {
      HStack(alignment: .firstTextBaseline) {
        self.title
        Spacer(minLength: 8)
        self.allLink
      }
    }
  }

  private var title: some View {
    Text("곧 만료되는 기프티콘 \(self.strip.count)개")
      .font(.headline)
      .snapRollingNumber(self.strip.count)
      .accessibilityAddTraits(.isHeader)
  }

  /// 기프티콘 목록을 연다. 줌 전환은 루트의 `navigationDestination` 이 기프티콘 **카드**를 출발점으로 건다(같은 출처를 여기 또 달지 않는다).
  private var allLink: some View {
    NavigationLink(value: ImageCategory.gifticon) {
      HStack(spacing: 2) {
        Text("모두 보기")
        Image(systemName: "chevron.right")
          .imageScale(.small)
      }
      .font(.subheadline)
      .foregroundStyle(SnapColor.accent)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("기프티콘 모두 보기"))
  }

  // MARK: 칩

  private var chips: some View {
    let pages = PhotoPages.pages(expiring: self.strip)
    let origin = PhotoDetailOrigin(visit: self.visit, section: 0)
    let moreCount = self.strip.count - self.strip.items.count
    return ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        // 칩은 상한(20) + "+k" 하나라 Lazy 가 아니다.
        HStack(alignment: .top, spacing: 12) {
          ForEach(Array(self.strip.items.enumerated()), id: \.element.id) { index, chip in
            NavigationLink(value: PhotoDetailRoute(pages: pages, index: index, origin: origin)) {
              self.chip(chip)
            }
            .buttonStyle(.snapCard)
            // 칩 하나가 접근성 요소 하나(카테고리 카드와 같은 배치). 썸네일은 장식이다(`CoverMosaic`).
            .accessibilityLabel(Self.accessibilityLabel(chip))
            // 칩 썸네일이 사진 상세 줌 전환의 출발점이 되게 연 곳을 넣는다(GifticonListView·CategoryView 와 같은 배치).
            .environment(\.photoDetailOrigin, origin)
          }
          if moreCount > 0 {
            self.moreChip(moreCount)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.viewAligned)
      // 부모 여백을 넘어 화면 끝까지 칩이 보이고, 처음·끝 칩은 다른 카드와 같은 선에 맞는다.
      .padding(.horizontal, -16)
      .contentMargins(.horizontal, 16, for: .scrollContent)
      // 상세에서 돌아와 다시 보일 때 이 방문의 돌아올 위치가 있으면 그 칩이 보이게 한 번 스크롤한다(이미 보이면 움직이지 않고,
      // 지금 띠에 없으면 아무것도 하지 않는다). 기프티콘 목록(`GifticonListView.list`)과 같은 규칙.
      .onAppear {
        guard let target = self.categoryModel.detailReturn, target.origin.visit == self.visit else { return }
        self.categoryModel.detailReturnApplied(visit: self.visit)
        proxy.scrollTo(target.id, anchor: nil)
      }
    }
  }

  private func chip(_ chip: ExpiringGifticon) -> some View {
    let place = Self.place(of: chip.item)
    return VStack(alignment: .leading, spacing: 6) {
      CoverMosaic([self.tile(chip.id)], fallback: ImageCategory.gifticon.glyph, aspectRatio: 1)
        .frame(width: self.side, height: self.side)
        // 사진 상세가 이 썸네일에서 커지며 열리고 닫을 때 여기로 줄어든다. 모서리는 CoverMosaic 의 모서리(14)와 같게.
        // D-n 배지는 출발점에 넣지 않는다(출발점 뒤에 overlay).
        .photoZoomSource(chip.id, cornerRadius: 14)
        .overlay(alignment: .topLeading) {
          GifticonDueBadge(due: chip.due, isUsed: false)
            .padding(4)
        }
      // 칩에는 날짜 글자가 없어 D-n 이 추정일 수 있음을 따로 보일 곳이 없으므로, 교환처·만료일 어느 쪽이 추정이어도 "추정"을 붙인다.
      VStack(alignment: .leading, spacing: 2) {
        Text(place ?? "교환처 모름")
          .font(.caption)
          .foregroundStyle(place != nil ? .primary : .secondary)
          .lineLimit(self.isAccessibilitySize ? 2 : 1)
        if !chip.item.estimatedFields.isEmpty {
          EstimatedBadge()
        }
      }
      .frame(width: self.side, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .onAppear { self.coverModel.cardAppeared(ids: [chip.id]) }
  }

  /// 상한을 넘는 몫. 상세 장이 아니라 기프티콘 목록을 연다.
  private func moreChip(_ count: Int) -> some View {
    NavigationLink(value: ImageCategory.gifticon) {
      VStack(alignment: .leading, spacing: 6) {
        Text("+\(count)")
          .font(.title3.bold().monospacedDigit())
          .foregroundStyle(SnapColor.accent)
          .frame(width: self.side, height: self.side)
          .background(SnapColor.blush, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        Text("더 보기")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(self.isAccessibilitySize ? 2 : 1)
          .frame(width: self.side, alignment: .leading)
      }
      .accessibilityElement(children: .ignore)
    }
    .buttonStyle(.snapCard)
    .accessibilityLabel(Text("기프티콘 \(count)개 더 보기"))
  }

  /// `LibraryCategoryCard.tiles` 와 같은 매핑.
  private func tile(_ id: ImageAsset.ID) -> CoverMosaic.Tile {
    switch self.coverModel.thumbnails[id] {
    case let .loaded(image):
      .image(image.cgImage, orientation: image.orientation)
    case .unavailable:
      .glyph
    case .loading, nil:
      .pending
    }
  }

  private static func place(of item: GifticonListItem) -> String? {
    if case let .extracted(info) = item.status {
      return info.redemptionPlace
    }
    return nil
  }

  /// "교환처, n일 남음"(오늘 만료면 "오늘 만료"). 추정 값이 있으면 ", 추정 포함".
  private static func accessibilityLabel(_ chip: ExpiringGifticon) -> Text {
    let place = Self.place(of: chip.item)
    let dueText = switch chip.due {
    case .remaining(days: 0): "오늘 만료"
    case let .remaining(days): "\(days)일 남음"
    case let .expired(daysAgo): "\(daysAgo)일 지남"
    }
    let text = "\(place ?? "교환처 모름"), \(dueText)"
    return Text(verbatim: chip.item.estimatedFields.isEmpty ? text : "\(text), 추정 포함")
  }
}
