import Core
import Foundation
import ImageIO
import PhotoLibraryTesting
import Testing
import UIKit
@testable import LibraryFeature

/// 여는 곳의 섹션 하나를 사진 상세의 장으로 바꾸는 규칙과 돌아올 섹션 고르기, 상세 경로 값, 확대 뷰의 방향 변환.
struct PhotoPagesTests {
  private let assets: [ImageAsset] = .stubs(count: 3)

  private func gifticon(_ asset: ImageAsset, isUsed: Bool = false) -> GifticonListItem {
    GifticonListItem(asset: asset, status: .checking, isUsed: isUsed)
  }

  @Test("사진 섹션은 받은 순서 그대로 장이 되고 기프티콘 정보가 없다")
  func pagesKeepOrderWithoutGifticon() {
    let pages = PhotoPages.pages(self.assets)

    #expect(pages.map(\.asset.id) == ["image-0", "image-1", "image-2"])
    #expect(pages.allSatisfy { $0.gifticon == nil })
  }

  @Test("기프티콘 섹션은 장마다 그 항목을 순서대로 싣는다")
  func gifticonPagesCarryItems() {
    let items = self.assets.map { self.gifticon($0) }

    let pages = PhotoPages.pages(gifticons: items)

    #expect(pages.map(\.asset.id) == ["image-0", "image-1", "image-2"])
    #expect(pages.map(\.gifticon) == items)
  }

  @Test("정리 후보는 기프티콘 후보만 그 항목을 싣고 비슷한 사진은 싣지 않는다")
  func candidatePagesCarryOnlyGifticons() {
    let item = self.gifticon(self.assets[0], isUsed: true)
    let candidates = [
      CleanupCandidate(gifticon: item, isSelectedByDefault: true),
      CleanupCandidate(similarPhoto: self.assets[1], isKept: true),
      CleanupCandidate(similarPhoto: self.assets[2], isKept: false),
    ]

    let pages = PhotoPages.pages(candidates: candidates)

    #expect(pages.map(\.asset.id) == ["image-0", "image-1", "image-2"])
    #expect(pages.map(\.gifticon) == [item, nil, nil])
  }

  @Test("곧 만료 띠는 칩 순서대로 장마다 그 기프티콘을 싣고, 상한 밖(\"+k\" 몫)은 장이 아니다")
  func expiringPagesCarryChips() throws {
    let today = try #require(LocalDate(year: 2026, month: 10, day: 19))
    let items = self.assets.enumerated().map { offset, asset in
      GifticonListItem(
        asset: asset,
        status: .extracted(GifticonInfo(expiryDate: today.addingDays(2 - offset), redemptionPlace: nil)),
        isUsed: false
      )
    }
    let strip = ExpiringGifticons.make(from: items, today: today, limit: 2)

    let pages = PhotoPages.pages(expiring: strip)

    #expect(strip.count == 3)
    #expect(pages.map(\.asset.id) == ["image-2", "image-1"])
    #expect(pages.map(\.gifticon) == [items[2], items[1]])
  }

  @Test("연 섹션에 그 사진이 있으면 다른 섹션에도 있어도 연 섹션으로 돌아온다")
  func returnSectionPrefersOpenedSection() {
    let sections = [["a", "b"], ["c"], ["b", "d"]]

    #expect(PhotoPages.returnSection(of: "b", preferred: 2, in: sections) == 2)
    #expect(PhotoPages.returnSection(of: "b", preferred: 0, in: sections) == 0)
  }

  @Test("연 섹션에 없거나 연 섹션 위치가 범위 밖이면 그 사진을 담은 첫 섹션, 어디에도 없으면 nil")
  func returnSectionFallsBack() {
    let sections = [["a", "b"], ["c"], ["b", "d"]]

    #expect(PhotoPages.returnSection(of: "b", preferred: 1, in: sections) == 0)
    #expect(PhotoPages.returnSection(of: "d", preferred: 5, in: sections) == 2)
    #expect(PhotoPages.returnSection(of: "d", preferred: -1, in: sections) == 2)
    #expect(PhotoPages.returnSection(of: "z", preferred: 0, in: sections) == nil)
    #expect(PhotoPages.returnSection(of: "a", preferred: 0, in: []) == nil)
  }

  @Test("한 장 경로는 장 하나·위치 0·연 곳 없음이다")
  func singleRoute() {
    let item = self.gifticon(self.assets[1])

    let route = PhotoDetailRoute(asset: self.assets[1], gifticon: item)

    #expect(route.pages == [PhotoPage(asset: self.assets[1], gifticon: item)])
    #expect(route.index == 0)
    #expect(route.origin == nil)
  }

  @Test("같은 스냅숏·위치·연 곳이면 같은 경로이고, 위치나 연 곳이 다르면 다르다")
  func routeEquality() {
    let pages = PhotoPages.pages(self.assets)
    let origin = PhotoDetailOrigin(visit: UUID(), section: 0)
    let route = PhotoDetailRoute(pages: pages, index: 1, origin: origin)

    #expect(route == PhotoDetailRoute(pages: PhotoPages.pages(self.assets), index: 1, origin: origin))
    #expect(route.hashValue == PhotoDetailRoute(pages: PhotoPages.pages(self.assets), index: 1, origin: origin)
      .hashValue)
    #expect(route != PhotoDetailRoute(pages: pages, index: 2, origin: origin))
    #expect(route != PhotoDetailRoute(pages: pages, index: 1, origin: PhotoDetailOrigin(visit: UUID(), section: 0)))
    #expect(route != PhotoDetailRoute(
      pages: pages,
      index: 1,
      origin: PhotoDetailOrigin(visit: origin.visit, section: 1)
    ))
    #expect(route != PhotoDetailRoute(pages: pages, index: 1, origin: nil))
    #expect(route != PhotoDetailRoute(pages: Array(pages.prefix(2)), index: 1, origin: origin))
  }

  @Test("이미지 방향은 같은 이름의 UIImage 방향으로 바뀐다")
  func orientationMapping() {
    let pairs: [(CGImagePropertyOrientation, UIImage.Orientation)] = [
      (.up, .up), (.upMirrored, .upMirrored), (.down, .down), (.downMirrored, .downMirrored),
      (.left, .left), (.leftMirrored, .leftMirrored), (.right, .right), (.rightMirrored, .rightMirrored),
    ]

    for (orientation, expected) in pairs {
      #expect(UIImage.Orientation(orientation) == expected)
    }
  }

  @Test("줌 출발점은 같은 사진이어도 방문 값이나 섹션이 다르면 다르다")
  func zoomSourceIDSeparatesOrigins() {
    let visit = UUID()
    let id = self.assets[0].id
    let source = PhotoZoomSourceID(origin: PhotoDetailOrigin(visit: visit, section: 0), id: id)

    #expect(source == PhotoZoomSourceID(origin: PhotoDetailOrigin(visit: visit, section: 0), id: id))
    #expect(source != PhotoZoomSourceID(origin: PhotoDetailOrigin(visit: visit, section: 1), id: id))
    #expect(source != PhotoZoomSourceID(origin: PhotoDetailOrigin(visit: UUID(), section: 0), id: id))
    #expect(source != PhotoZoomSourceID(origin: PhotoDetailOrigin(visit: visit, section: 0), id: self.assets[1].id))
  }
}
