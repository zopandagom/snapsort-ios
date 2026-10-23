import Testing
@testable import Core

/// 닫힌 목록(쇼핑몰·브랜드·대화 앱·지역)의 형식과 저장 키 왕복 (docs/ARCHITECTURE.md §4 캡처 묶음 추출).
struct CaptureGroupTablesTests {
  @Test("몰·브랜드 id 는 겹치지 않고 이름이 있다")
  func idsAreUnique() {
    #expect(Set(ShoppingMall.all.map(\.id)).count == ShoppingMall.all.count)
    #expect(Set(ShoppingBrand.all.map(\.id)).count == ShoppingBrand.all.count)
    #expect(ShoppingMall.all.allSatisfy { !$0.name.isEmpty })
    #expect(ShoppingBrand.all.allSatisfy { !$0.name.isEmpty })
  }

  @Test("별칭은 정규화한 꼴(소문자, 공백 없음)이고 비어 있지 않다")
  func aliasesAreNormalized() {
    let aliases = Self.mallAliases + Self.brandAliases + ChatApp.allCases.flatMap(\.signatures)
    #expect(aliases.allSatisfy { !$0.isEmpty && $0 == $0.lowercased() && !$0.contains(where: \.isWhitespace) })
    #expect(ShoppingMall.all.flatMap(\.domains).allSatisfy { $0 == $0.lowercased() && $0.contains(".") })
    #expect(ShoppingMall.all.allSatisfy { !$0.words.isEmpty || !$0.lines.isEmpty || !$0.domains.isEmpty })
    #expect(ShoppingBrand.all.allSatisfy { !$0.words.isEmpty || !$0.lines.isEmpty })
  }

  @Test("몰끼리, 브랜드끼리, 몰과 브랜드, 대화 앱끼리 별칭이 겹치지 않는다")
  func aliasesDoNotOverlap() {
    #expect(Set(Self.mallAliases).count == Self.mallAliases.count)
    #expect(Set(Self.brandAliases).count == Self.brandAliases.count)
    #expect(Set(Self.mallAliases).isDisjoint(with: Self.brandAliases))
    let signatures = ChatApp.allCases.flatMap(\.signatures)
    #expect(Set(signatures).count == signatures.count)
  }

  @Test("저장 키로 표의 모든 값을 다시 찾는다")
  func roundTripsEveryKey() {
    for mall in ShoppingMall.all {
      #expect(ShoppingMall(id: mall.id) == mall)
    }
    for brand in ShoppingBrand.all {
      #expect(ShoppingBrand(id: brand.id) == brand)
    }
    for app in ChatApp.allCases {
      #expect(ChatApp(rawValue: app.rawValue) == app)
    }
    let regions = KoreanProvince.allCases.map { KoreanRegion(province: $0, district: nil) }
      + KoreanAdministrativeDivisions.entries.filter { !$0.isGeneralDistrict }
      .map { KoreanRegion(province: $0.province, district: $0.city) }
    #expect(regions.count == 17 + 229)
    for region in regions {
      #expect(KoreanRegion(id: region.id) == region)
    }
  }

  @Test("모르는 id·일반구 id·소속이 틀린 id·빈 id 는 nil 이다")
  func unknownKeysAreNil() {
    #expect(ShoppingMall(id: "noSuchMall") == nil)
    #expect(ShoppingBrand(id: "noSuchBrand") == nil)
    #expect(ChatApp(rawValue: "noSuchApp") == nil)
    for id in ["", "nowhere", "gyeonggi:분당구", "busan:강남구", "seoul:", "seoul:강남구:x", "sejong:세종시", "서울"] {
      #expect(KoreanRegion(id: id) == nil)
    }
  }

  @Test("지역의 식별자·이름·순서")
  func regionIdentity() throws {
    let gangnam = try #require(KoreanRegion(id: "seoul:강남구"))
    let jeju = try #require(KoreanRegion(id: "jeju"))
    #expect(gangnam.title == "서울 강남구")
    #expect(jeju.title == "제주")
    #expect(KoreanRegion(province: .gyeonggi, district: "성남시").title == "경기 성남시")
    #expect((jeju < gangnam) == ("jeju" < "seoul:강남구"))
    #expect([gangnam, jeju].sorted().map(\.id) == ["jeju", "seoul:강남구"])
    #expect(KoreanProvince.allCases.map(\.name).count == 17)
  }

  private static var mallAliases: [String] {
    ShoppingMall.all.flatMap { $0.words + $0.lines }
  }

  private static var brandAliases: [String] {
    ShoppingBrand.all.flatMap { $0.words + $0.lines }
  }
}
