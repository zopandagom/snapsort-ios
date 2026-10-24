/// 한국 행정구역 표: 시·도 별칭, 시·도별 시·군·구, 시 안의 일반구 (docs/ARCHITECTURE.md §4 캡처 정보 추출·캡처 묶음 추출).
/// 주소 규칙(`CaptureInfoExtractor+KoreanAddress`)이 보통 낱말("다시"·"축구"·"가면")을 시·군·구로 받지 않도록 끝 글자가 아니라
/// 이 목록으로 대조하고, 지도 캡처 지역(`KoreanRegion`)도 같은 표로 찾는다. 목록에 없는 이름은 주소·지역을 놓칠 뿐 엉뚱한 값을 만들지 않는다.
/// 이 표가 원본이고 주소 규칙이 쓰는 `provinces`·`sejong`·`districts` 는 표에서 만든다(주소 추출 동작은 그대로다).
/// 2026년 10월 기준으로 적었다(인천 2026년 7월 개편: 제물포구·영종구·검단구, 화성시 2025년 일반구 설치). 공식 자료와 대조하지 않았으므로
/// 시·도 소속을 포함해 행정구역이 바뀌거나 빠진 이름을 찾으면 고친다. 표를 바꾸면 `CaptureGroupExtractor.rulesVersion` 을 올린다.
enum KoreanAdministrativeDivisions {
  /// 시·군·구 이름의 한 소속. `city` 는 지역으로 올릴 이름: 일반구면 소속 시 이름("분당구" → "성남시"), 아니면 `name` 과 같다.
  struct Entry {
    let province: KoreanProvince
    let name: String
    let city: String
    var isGeneralDistrict: Bool { self.name != self.city }
  }

  /// 시·도 별칭. 같은 시·도의 줄인 이름("서울시"·"서울")을 함께 둔다.
  private static let provinceAliasTable: [(province: KoreanProvince, aliases: [String])] = [
    (.seoul, ["서울특별시", "서울시", "서울"]),
    (.busan, ["부산광역시", "부산시", "부산"]),
    (.daegu, ["대구광역시", "대구시", "대구"]),
    (.incheon, ["인천광역시", "인천시", "인천"]),
    (.gwangju, ["광주광역시", "광주"]),
    (.daejeon, ["대전광역시", "대전시", "대전"]),
    (.ulsan, ["울산광역시", "울산시", "울산"]),
    (.sejong, ["세종특별자치시", "세종시", "세종"]),
    (.gyeonggi, ["경기도", "경기"]),
    (.gangwon, ["강원특별자치도", "강원도", "강원"]),
    (.chungbuk, ["충청북도", "충북"]),
    (.chungnam, ["충청남도", "충남"]),
    (.jeonbuk, ["전북특별자치도", "전라북도", "전북"]),
    (.jeonnam, ["전라남도", "전남"]),
    (.gyeongbuk, ["경상북도", "경북"]),
    (.gyeongnam, ["경상남도", "경남"]),
    (.jeju, ["제주특별자치도", "제주도", "제주"]),
  ]

  /// 시·도별 시·군·구(일반구 제외). 세종은 시·군·구가 없다.
  private static let districtTable: [(province: KoreanProvince, names: [String])] = [
    (.seoul, [
      "종로구", "중구", "용산구", "성동구", "광진구", "동대문구", "중랑구", "성북구", "강북구", "도봉구", "노원구", "은평구",
      "서대문구", "마포구", "양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구", "서초구", "강남구", "송파구",
      "강동구",
    ]),
    (.busan, [
      "중구", "서구", "동구", "영도구", "부산진구", "동래구", "남구", "북구", "해운대구", "사하구", "금정구", "강서구", "연제구",
      "수영구", "사상구", "기장군",
    ]),
    (.daegu, ["중구", "동구", "서구", "남구", "북구", "수성구", "달서구", "달성군", "군위군"]),
    (.incheon, [
      "제물포구", "영종구", "미추홀구", "연수구", "남동구", "부평구", "계양구", "서구", "검단구", "강화군", "옹진군",
    ]),
    (.gwangju, ["동구", "서구", "남구", "북구", "광산구"]),
    (.daejeon, ["동구", "중구", "서구", "유성구", "대덕구"]),
    (.ulsan, ["중구", "남구", "동구", "북구", "울주군"]),
    (.gyeonggi, [
      "수원시", "성남시", "의정부시", "안양시", "부천시", "광명시", "평택시", "동두천시", "안산시", "고양시", "과천시", "구리시",
      "남양주시", "오산시", "시흥시", "군포시", "의왕시", "하남시", "용인시", "파주시", "이천시", "안성시", "김포시", "화성시",
      "광주시", "양주시", "포천시", "여주시", "연천군", "가평군", "양평군",
    ]),
    (.gangwon, [
      "춘천시", "원주시", "강릉시", "동해시", "태백시", "속초시", "삼척시", "홍천군", "횡성군", "영월군", "평창군", "정선군",
      "철원군", "화천군", "양구군", "인제군", "고성군", "양양군",
    ]),
    (.chungbuk, [
      "청주시", "충주시", "제천시", "보은군", "옥천군", "영동군", "증평군", "진천군", "괴산군", "음성군", "단양군",
    ]),
    (.chungnam, [
      "천안시", "공주시", "보령시", "아산시", "서산시", "논산시", "계룡시", "당진시", "금산군", "부여군", "서천군", "청양군",
      "홍성군", "예산군", "태안군",
    ]),
    (.jeonbuk, [
      "전주시", "군산시", "익산시", "정읍시", "남원시", "김제시", "완주군", "진안군", "무주군", "장수군", "임실군", "순창군",
      "고창군", "부안군",
    ]),
    (.jeonnam, [
      "목포시", "여수시", "순천시", "나주시", "광양시", "담양군", "곡성군", "구례군", "고흥군", "보성군", "화순군", "장흥군",
      "강진군", "해남군", "영암군", "무안군", "함평군", "영광군", "장성군", "완도군", "진도군", "신안군",
    ]),
    (.gyeongbuk, [
      "포항시", "경주시", "김천시", "안동시", "구미시", "영주시", "영천시", "상주시", "문경시", "경산시", "의성군", "청송군",
      "영양군", "영덕군", "청도군", "고령군", "성주군", "칠곡군", "예천군", "봉화군", "울진군", "울릉군",
    ]),
    (.gyeongnam, [
      "창원시", "진주시", "통영시", "사천시", "김해시", "밀양시", "거제시", "양산시", "의령군", "함안군", "창녕군", "고성군",
      "남해군", "하동군", "산청군", "함양군", "거창군", "합천군",
    ]),
    (.jeju, ["제주시", "서귀포시"]),
  ]

  private struct GeneralDistrictGroup {
    let province: KoreanProvince
    let city: String
    let names: [String]
  }

  /// 시 안의 일반구. 시는 `districtTable` 의 같은 시·도에 있어야 한다(표 테스트가 확인한다).
  private static let generalDistrictTable: [GeneralDistrictGroup] = [
    GeneralDistrictGroup(province: .gyeonggi, city: "수원시", names: ["장안구", "권선구", "팔달구", "영통구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "성남시", names: ["수정구", "중원구", "분당구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "안양시", names: ["만안구", "동안구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "안산시", names: ["상록구", "단원구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "고양시", names: ["덕양구", "일산동구", "일산서구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "용인시", names: ["처인구", "기흥구", "수지구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "부천시", names: ["원미구", "소사구", "오정구"]),
    GeneralDistrictGroup(province: .gyeonggi, city: "화성시", names: ["만세구", "효행구", "병점구", "동탄구"]),
    GeneralDistrictGroup(province: .chungbuk, city: "청주시", names: ["상당구", "서원구", "흥덕구", "청원구"]),
    GeneralDistrictGroup(province: .chungnam, city: "천안시", names: ["동남구", "서북구"]),
    GeneralDistrictGroup(province: .jeonbuk, city: "전주시", names: ["완산구", "덕진구"]),
    GeneralDistrictGroup(province: .gyeongbuk, city: "포항시", names: ["남구", "북구"]),
    GeneralDistrictGroup(province: .gyeongnam, city: "창원시", names: ["의창구", "성산구", "마산합포구", "마산회원구", "진해구"]),
  ]

  /// 세종의 읍·면.
  static let sejongTowns: Set = [
    "조치원읍", "연기면", "연동면", "부강면", "금남면", "장군면", "연서면", "전의면", "전동면", "소정면",
  ]

  /// 그 시·도의 모든 별칭 ("서울특별시"·"서울시"·"서울"). 검색이 지역 이름을 대조할 때 쓴다.
  static func aliases(of province: KoreanProvince) -> [String] {
    self.provinceAliasTable.first { $0.province == province }?.aliases ?? []
  }

  /// 시·도 별칭 → 시·도 (세종 포함).
  static let provinceAliases: [String: KoreanProvince] = {
    var aliases: [String: KoreanProvince] = [:]
    for (province, names) in Self.provinceAliasTable {
      for name in names {
        aliases[name] = province
      }
    }
    return aliases
  }()

  /// 주소 규칙이 쓰는 시·도 별칭 (세종 제외).
  static let provinces: Set<String> = Set(
    Self.provinceAliasTable.filter { $0.province != .sejong }.flatMap(\.aliases)
  )

  /// 세종. 시·군·구가 없어 시·도 바로 뒤에 읍·면이나 도로명이 온다.
  static let sejong: Set<String> = Set(Self.provinceAliasTable.filter { $0.province == .sejong }.flatMap(\.aliases))

  /// 지도 지역에서 시·도만으로 받는 별칭. "경기"(시합)·"세종"(세종대왕 등)은 보통 낱말이라 시·도만으로는 받지 않는다
  /// (시·군·구와 짝이면 받는다).
  static let standaloneProvinceAliases: Set<String> = Set(Self.provinceAliases.keys).subtracting(["경기", "세종"])

  /// 시·군·구와 시 안의 일반구의 모든 소속.
  static let entries: [Entry] = {
    var entries: [Entry] = []
    for (province, names) in Self.districtTable {
      entries += names.map { Entry(province: province, name: $0, city: $0) }
    }
    for group in Self.generalDistrictTable {
      entries += group.names.map { Entry(province: group.province, name: $0, city: group.city) }
    }
    return entries
  }()

  /// 시·군·구와 시 안의 일반구. 여러 시·도에 같은 이름("중구"·"고성군")이 있어도 한 번만 둔다.
  static let districts: Set<String> = Set(Self.entries.map(\.name))

  private static let entriesByName: [String: [Entry]] = Dictionary(grouping: Self.entries, by: \.name)

  /// 시·군·구 이름의 소속 지역. 일반구는 소속 시로 올린 지역이다("분당구" → 경기 성남시). 여러 시·도에 있으면 여러 개.
  static func regions(named district: String) -> Set<KoreanRegion> {
    Set((self.entriesByName[district] ?? []).map { KoreanRegion(province: $0.province, district: $0.city) })
  }

  /// 그 시·도에 있는 이름의 소속. 없으면 nil.
  static func entry(named district: String, in province: KoreanProvince) -> Entry? {
    self.entriesByName[district]?.first { $0.province == province }
  }

  /// 일반구가 아닌 시·군·구 `district` 가 그 시·도에 있는지(`KoreanRegion(id:)` 가 확인한다).
  static func hasDistrict(_ district: String, in province: KoreanProvince) -> Bool {
    guard let entry = Self.entry(named: district, in: province) else { return false }
    return !entry.isGeneralDistrict
  }

  /// 단독으로 받지 않는 시·군·구 이름: 표에서 여러 시·도에 있는 이름 7개("중구"·"강서구"·"고성군"·"남구"·"동구"·"북구"·"서구")와
  /// "광주시"(경기 광주시이지만 광주광역시를 "광주시"로도 써서 헷갈린다).
  static let ambiguousStandaloneDistricts: Set<String> = {
    var names = Set(Self.entriesByName.keys.filter { Self.regions(named: $0).count > 1 })
    names.insert("광주시")
    return names
  }()
}
