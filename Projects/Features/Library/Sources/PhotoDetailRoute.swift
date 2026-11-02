import Core
import Foundation

/// 사진 상세에서 넘기는 한 장. 기프티콘 목록·정리 화면의 기프티콘 후보에서 연 장만 `gifticon` 이 있고,
/// 이 장만 상세가 기프티콘 정보·사용함 버튼·바코드를 보인다. 다른 카테고리 격자에서 연 같은 이미지에는 주소·번호 행동만 보인다.
public struct PhotoPage: Hashable, Sendable {
  public let asset: ImageAsset
  public let gifticon: GifticonListItem?

  public init(asset: ImageAsset, gifticon: GifticonListItem? = nil) {
    self.asset = asset
    self.gifticon = gifticon
  }
}

/// 사진 상세로 가는 이동 값. 상세는 카테고리 화면·여행 폴더 상세의 칸과 기프티콘·영수증 목록의 줄, 검색 결과의 사진 줄, 정리 화면의 후보 줄에서만 연다.
/// 누른 칸·줄이 속한 섹션 하나를 그 화면에 보이던 순서 그대로 스냅숏으로 싣는다(docs/ARCHITECTURE.md §4 카테고리 화면).
/// 상세는 이 섹션 안에서만 넘기고, 열려 있는 동안 원래 목록이 바뀌어도 순서는 그대로다.
struct PhotoDetailRoute: Hashable {
  /// 비어 있지 않다. 한 섹션의 장들.
  let pages: [PhotoPage]
  /// 누른 장의 위치. `pages` 범위 안이다.
  let index: Int
  /// 돌아올 위치를 받을 화면(`CategoryModel.detailReturn`). 한 장 상세(공개 init·Example)는 nil.
  let origin: PhotoDetailOrigin?

  /// 범위 밖 위치는 가장 가까운 장으로 맞춘다.
  init(pages: [PhotoPage], index: Int, origin: PhotoDetailOrigin?) {
    self.pages = pages
    self.index = min(max(index, 0), max(pages.count - 1, 0))
    self.origin = origin
  }

  /// 한 장짜리 상세. 돌아올 위치가 없다.
  init(asset: ImageAsset, gifticon: GifticonListItem? = nil) {
    self.init(pages: [PhotoPage(asset: asset, gifticon: gifticon)], index: 0, origin: nil)
  }

  /// 칸마다 만드는 값이라 큰 섹션 배열 전체를 해시하지 않는다(같은 값이면 이 셋도 같다).
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.index)
    hasher.combine(self.pages.count)
    if self.pages.indices.contains(self.index) {
      hasher.combine(self.pages[self.index])
    }
    hasher.combine(self.origin)
  }
}

/// 여는 곳이 그리는 섹션 하나를 상세의 장으로 바꾸고, 돌아올 때 스크롤할 섹션을 고른다.
enum PhotoPages {
  /// 카테고리 격자·영수증 목록·여행 폴더 상세·검색 결과의 사진. 기프티콘 정보 없이 주소·번호 행동만.
  static func pages(_ assets: [ImageAsset]) -> [PhotoPage] {
    assets.map { PhotoPage(asset: $0) }
  }

  /// 기프티콘 목록. 장마다 그 항목을 싣는다.
  static func pages(gifticons: [GifticonListItem]) -> [PhotoPage] {
    gifticons.map { PhotoPage(asset: $0.asset, gifticon: $0) }
  }

  /// 정리 화면. 기프티콘 후보만 그 항목을 싣고, 비슷한 사진은 주소·번호 행동만.
  static func pages(candidates: [CleanupCandidate]) -> [PhotoPage] {
    candidates.map { PhotoPage(asset: $0.asset, gifticon: $0.gifticon) }
  }

  /// 돌아올 때 스크롤할 섹션 위치. 같은 이미지가 두 섹션에 들 수 있는 화면(카테고리 지역별 묶기, 여행 폴더 상세)이 쓴다.
  /// 연 섹션(`preferred`)에 그 이미지가 있으면 그 섹션, 없으면 그 이미지를 담은 첫 섹션, 어디에도 없으면 nil(스크롤하지 않는다).
  static func returnSection(of id: ImageAsset.ID, preferred: Int, in sections: [[ImageAsset.ID]]) -> Int? {
    if sections.indices.contains(preferred), sections[preferred].contains(id) {
      return preferred
    }
    return sections.firstIndex { $0.contains(id) }
  }
}
