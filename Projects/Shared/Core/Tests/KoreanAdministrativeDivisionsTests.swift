import Testing
@testable import Core

/// 시·도 소속은 공식 자료와 대조하지 않은 값이다 (docs/ARCHITECTURE.md §4 캡처 묶음 추출).
struct KoreanAdministrativeDivisionsTests {
  @Test("주소 규칙이 쓰는 집합은 표에서 만들어도 그대로다: 시·군·구 246개, 시·도 별칭 41개, 세종 3개")
  func addressSetsKeepTheirContents() {
    #expect(KoreanAdministrativeDivisions.districts.count == 246)
    #expect(KoreanAdministrativeDivisions.provinces.count == 41)
    #expect(KoreanAdministrativeDivisions.sejong == ["세종특별자치시", "세종시", "세종"])
    #expect(KoreanAdministrativeDivisions.provinceAliases.count == 44)
    #expect(KoreanAdministrativeDivisions.districts.isSuperset(of: ["분당구", "고성군", "마산합포구", "제물포구", "광주시"]))
    #expect(KoreanAdministrativeDivisions.provinces.isSuperset(of: ["제주도", "강원특별자치도", "서울", "광주"]))
    #expect(!KoreanAdministrativeDivisions.provinces.contains("세종"))
  }

  @Test("시·도별 시·군·구는 229개이고, 일반구 항목 39개는 모두 그 시·도 표에 있는 시로 올라간다")
  func tableCounts() {
    let plain = KoreanAdministrativeDivisions.entries.filter { !$0.isGeneralDistrict }
    let counts = Dictionary(grouping: plain, by: \.province).mapValues(\.count)
    #expect(counts == [
      .seoul: 25, .busan: 16, .daegu: 9, .incheon: 11, .gwangju: 5, .daejeon: 5, .ulsan: 5, .gyeonggi: 31,
      .gangwon: 18, .chungbuk: 11, .chungnam: 15, .jeonbuk: 14, .jeonnam: 22, .gyeongbuk: 22, .gyeongnam: 18, .jeju: 2,
    ])
    #expect(plain.count == 229)
    let general = KoreanAdministrativeDivisions.entries.filter(\.isGeneralDistrict)
    #expect(general.count == 39)
    for entry in general {
      #expect(KoreanAdministrativeDivisions.hasDistrict(entry.city, in: entry.province))
    }
  }

  @Test("여러 시·도에 있는 이름은 표에서 계산한 7개와 광주시다")
  func ambiguousDistricts() {
    #expect(KoreanAdministrativeDivisions.ambiguousStandaloneDistricts == [
      "중구", "강서구", "고성군", "남구", "동구", "북구", "서구", "광주시",
    ])
    #expect(KoreanAdministrativeDivisions.regions(named: "남구").count == 5)
    #expect(KoreanAdministrativeDivisions.regions(named: "분당구") == [KoreanRegion(province: .gyeonggi, district: "성남시")])
    #expect(KoreanAdministrativeDivisions.regions(named: "없는구").isEmpty)
  }

  @Test("단독으로 받는 시·도 별칭은 경기와 세종을 뺀 나머지다")
  func standaloneAliases() {
    #expect(!KoreanAdministrativeDivisions.standaloneProvinceAliases.contains("경기"))
    #expect(!KoreanAdministrativeDivisions.standaloneProvinceAliases.contains("세종"))
    #expect(KoreanAdministrativeDivisions.standaloneProvinceAliases.isSuperset(of: ["경기도", "세종시", "세종특별자치시", "제주"]))
    #expect(KoreanAdministrativeDivisions.standaloneProvinceAliases.count == 42)
  }

  @Test("aliases(of:) 는 그 시·도의 모든 별칭을 표 순서로 준다")
  func provinceAliasesList() {
    #expect(KoreanAdministrativeDivisions.aliases(of: .seoul) == ["서울특별시", "서울시", "서울"])
    #expect(KoreanAdministrativeDivisions.aliases(of: .gwangju) == ["광주광역시", "광주"])
    for province in KoreanProvince.allCases {
      let aliases = KoreanAdministrativeDivisions.aliases(of: province)
      #expect(!aliases.isEmpty)
      #expect(aliases.allSatisfy { KoreanAdministrativeDivisions.provinceAliases[$0] == province })
    }
  }
}
