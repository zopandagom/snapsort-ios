import Core
import Foundation
import Testing

struct CaptureGroupSectionsTests {
  private static let coupang = ShoppingMall(id: "coupang")!
  private static let musinsa = ShoppingMall(id: "musinsa")!
  private static let nike = ShoppingBrand(id: "nike")!
  private static let gangnam = KoreanRegion(id: "seoul:강남구")!
  private static let haeundae = KoreanRegion(id: "busan:해운대구")!

  @Test("쇼핑몰별: 가장 최근 이미지가 있는 몰부터, 그 뒤에 몰 모름, 맨 끝에 확인 중이고 섹션 안은 최신순이다")
  func sectionsByMall() {
    let sections = CaptureGroupSections.sections(
      of: [
        self.item("a", 100, mall: Self.coupang),
        self.item("b", 300, mall: Self.musinsa),
        self.item("c", 200, mall: Self.coupang),
        self.item("d", 400),
        self.item("e", 500, checking: true),
        self.item("f", 50),
        self.item("g", 450, checking: true),
      ],
      grouping: .mall
    )

    #expect(sections.map(\.kind) == [
      .group(.mall(Self.musinsa)), .group(.mall(Self.coupang)), .unknown, .checking,
    ])
    #expect(sections.map { $0.assets.map(\.id) } == [["b"], ["c", "a"], ["d", "f"], ["e", "g"]])
  }

  @Test("생성일 없는 묶음은 뒤에 두고, 빈 섹션은 만들지 않는다")
  func undatedGroupsGoLast() {
    let sections = CaptureGroupSections.sections(
      of: [self.item("undated", nil, mall: Self.coupang), self.item("dated", 100, mall: Self.musinsa)],
      grouping: .mall
    )

    #expect(sections.map(\.kind) == [.group(.mall(Self.musinsa)), .group(.mall(Self.coupang))])
    #expect(CaptureGroupSections.sections(of: [], grouping: .mall).isEmpty)
    #expect(CaptureGroupSections.sections(of: [self.item("a", 1, mall: Self.coupang)], grouping: .mall).count == 1)
  }

  @Test("브랜드별·앱별은 그 필드로 묶는다")
  func sectionsByBrandAndApp() {
    let items = [
      item("a", 100, brand: Self.nike),
      self.item("b", 200, chatApp: .kakaoTalk),
      self.item("c", 300, chatApp: .messages),
    ]

    #expect(CaptureGroupSections.sections(of: items, grouping: .brand).map(\.kind)
      == [.group(.brand(Self.nike)), .unknown])
    #expect(CaptureGroupSections.sections(of: items, grouping: .chatApp).map(\.kind)
      == [.group(.chatApp(.messages)), .group(.chatApp(.kakaoTalk)), .unknown])
  }

  @Test("지역별: 한 이미지가 지역마다 한 섹션에 들고, 빈 집합은 지역 모름이다")
  func sectionsByRegionPutImageInEveryRegion() {
    let sections = CaptureGroupSections.sections(
      of: [
        self.item("both", 300, regions: [Self.gangnam, Self.haeundae]),
        self.item("seoul", 200, regions: [Self.gangnam]),
        self.item("none", 100),
      ],
      grouping: .region
    )

    // 두 섹션의 가장 최근 이미지가 같으면 지역 식별자 순(busan < seoul)이다.
    #expect(sections.map(\.kind) == [.group(.region(Self.haeundae)), .group(.region(Self.gangnam)), .unknown])
    #expect(sections.map { $0.assets.map(\.id) } == [["both"], ["both", "seoul"], ["none"]])
    #expect(sections.map(\.id) == sections.map(\.kind))
  }

  @Test("묶음 키의 섹션 이름")
  func keyTitles() {
    #expect(CaptureGroupKey.mall(Self.coupang).title == "쿠팡")
    #expect(CaptureGroupKey.brand(Self.nike).title == "나이키")
    #expect(CaptureGroupKey.chatApp(.kakaoTalk).title == "카카오톡")
    #expect(CaptureGroupKey.region(Self.gangnam).title == "서울 강남구")
  }

  @Test("카테고리별 묶기 순서")
  func groupingsForCategory() {
    #expect(CaptureGrouping.groupings(for: .shopping) == [.mall, .brand])
    #expect(CaptureGrouping.groupings(for: .chat) == [.chatApp])
    #expect(CaptureGrouping.groupings(for: .map) == [.region])
    for category in ImageCategory.allCases where ![.shopping, .chat, .map].contains(category) {
      #expect(CaptureGrouping.groupings(for: category).isEmpty)
    }
  }

  private func item(
    _ id: String,
    _ created: TimeInterval?,
    mall: ShoppingMall? = nil,
    brand: ShoppingBrand? = nil,
    chatApp: ChatApp? = nil,
    regions: Set<KoreanRegion> = [],
    checking: Bool = false
  ) -> CaptureGroupItem {
    CaptureGroupItem(
      asset: ImageAsset(
        id: id,
        creationDate: created.map { Date(timeIntervalSince1970: $0) },
        coordinate: nil,
        pixelWidth: 1170,
        pixelHeight: 2532,
        isScreenshot: true
      ),
      status: checking
        ? .checking
        : .extracted(CaptureGroups(mall: mall, brand: brand, chatApp: chatApp, regions: regions))
    )
  }
}
