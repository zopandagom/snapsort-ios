/// 쇼핑 브랜드 닫힌 목록의 한 브랜드 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). `id` 는 저장 키라 바꾸지 않는다.
/// 범위는 한국 쇼핑 캡처에 자주 나오는 스포츠·아웃도어·패션·명품·뷰티·전자·생활 브랜드이고, 임시 목록이다(실기기 정확도 측정에서 조정한다).
/// 이름이 일반 낱말이기도 한 브랜드(apple·puma·coach·guess·gap, "자라"·"게스"·"코치"·"보스"·"삼성" 등)는 줄 별칭만 둔다.
/// 제품 이름(아이폰 등)은 별칭으로 두지 않는다. 목록을 바꾸면 `CaptureGroupExtractor.rulesVersion` 을 올린다.
public struct ShoppingBrand: Sendable, Hashable, Identifiable {
  public let id: String
  /// 섹션 이름(표의 값. OCR 텍스트가 아니다).
  public let name: String
  /// 낱말 대조 별칭(정규화한 꼴: 소문자, 공백 없음).
  let words: [String]
  /// 줄 대조 별칭(정규화한 줄 전체가 같을 때만).
  let lines: [String]

  /// 표에서 찾는다. 없으면 nil.
  public init?(id: String) {
    guard let brand = Self.all.first(where: { $0.id == id }) else { return nil }
    self = brand
  }

  private init(_ id: String, _ name: String, words: [String] = [], lines: [String] = []) {
    self.id = id
    self.name = name
    self.words = words
    self.lines = lines
  }

  /// 표. 넣지 않은 것: "갤럭시"(케이스·액세서리 판매처가 흔히 씀), "mac"(Apple Mac·MAC 화장품), "삼성카드" 류 결제 이름.
  public static let all: [ShoppingBrand] = [
    ShoppingBrand("nike", "나이키", words: ["나이키", "nike"]),
    ShoppingBrand("adidas", "아디다스", words: ["아디다스", "adidas"]),
    ShoppingBrand("newBalance", "뉴발란스", words: ["뉴발란스", "newbalance"]),
    ShoppingBrand("puma", "푸마", words: ["푸마"], lines: ["puma"]),
    ShoppingBrand("asics", "아식스", words: ["아식스", "asics"]),
    ShoppingBrand("underArmour", "언더아머", words: ["언더아머", "underarmour"]),
    ShoppingBrand("theNorthFace", "노스페이스", words: ["노스페이스", "thenorthface", "northface"]),
    ShoppingBrand("patagonia", "파타고니아", words: ["파타고니아", "patagonia"]),
    ShoppingBrand("arcteryx", "아크테릭스", words: ["아크테릭스", "arcteryx"]),
    ShoppingBrand("salomon", "살로몬", words: ["살로몬", "salomon"]),
    ShoppingBrand("hoka", "호카", words: ["호카", "hoka"]),
    ShoppingBrand("fila", "휠라", words: ["휠라", "fila"]),
    ShoppingBrand("converse", "컨버스", lines: ["컨버스", "converse"]),
    ShoppingBrand("vans", "반스", words: ["반스"], lines: ["vans"]),
    ShoppingBrand("crocs", "크록스", words: ["크록스", "crocs"]),
    ShoppingBrand("discovery", "디스커버리", words: ["디스커버리익스페디션"], lines: ["디스커버리", "discovery"]),
    ShoppingBrand("mlb", "MLB", lines: ["mlb"]),
    ShoppingBrand("lululemon", "룰루레몬", words: ["룰루레몬", "lululemon"]),
    ShoppingBrand("xexymix", "젝시믹스", words: ["젝시믹스", "xexymix"]),
    ShoppingBrand("uniqlo", "유니클로", words: ["유니클로", "uniqlo"]),
    ShoppingBrand("zara", "자라", words: ["zara"], lines: ["자라"]),
    ShoppingBrand("hm", "H&M", words: ["h&m", "에이치앤엠"]),
    ShoppingBrand("muji", "무인양품", words: ["무인양품", "muji"]),
    ShoppingBrand("spao", "스파오", words: ["스파오", "spao"]),
    ShoppingBrand("topten", "탑텐", words: ["탑텐", "topten"]),
    ShoppingBrand(
      "ralphLauren", "폴로 랄프로렌",
      words: ["랄프로렌", "ralphlauren", "폴로랄프로렌", "poloralphlauren"], lines: ["폴로", "polo"]
    ),
    ShoppingBrand("tommyHilfiger", "타미힐피거", words: ["타미힐피거", "tommyhilfiger"]),
    ShoppingBrand("levis", "리바이스", words: ["리바이스", "levis"]),
    ShoppingBrand("calvinKlein", "캘빈클라인", words: ["캘빈클라인", "calvinklein"]),
    ShoppingBrand("guess", "게스", lines: ["게스", "guess"]),
    ShoppingBrand("gap", "갭", lines: ["갭", "gap"]),
    ShoppingBrand("gucci", "구찌", words: ["구찌", "gucci"]),
    ShoppingBrand("prada", "프라다", words: ["프라다", "prada"]),
    ShoppingBrand("louisVuitton", "루이비통", words: ["루이비통", "louisvuitton"]),
    ShoppingBrand("chanel", "샤넬", words: ["샤넬", "chanel"]),
    ShoppingBrand("dior", "디올", words: ["디올", "dior"]),
    ShoppingBrand("hermes", "에르메스", words: ["에르메스", "hermès", "hermes"]),
    ShoppingBrand("burberry", "버버리", words: ["버버리", "burberry"]),
    ShoppingBrand("celine", "셀린느", words: ["셀린느", "celine"]),
    ShoppingBrand("saintLaurent", "생로랑", words: ["생로랑", "saintlaurent"]),
    ShoppingBrand("balenciaga", "발렌시아가", words: ["발렌시아가", "balenciaga"]),
    ShoppingBrand("bottegaVeneta", "보테가베네타", words: ["보테가베네타", "bottegaveneta"]),
    ShoppingBrand("moncler", "몽클레르", words: ["몽클레르", "moncler"]),
    ShoppingBrand("coach", "코치", lines: ["코치", "coach"]),
    ShoppingBrand("miuMiu", "미우미우", words: ["미우미우", "miumiu"]),
    ShoppingBrand("rolex", "롤렉스", words: ["롤렉스", "rolex"]),
    ShoppingBrand("sulwhasoo", "설화수", words: ["설화수", "sulwhasoo"]),
    ShoppingBrand("innisfree", "이니스프리", words: ["이니스프리", "innisfree"]),
    ShoppingBrand("laneige", "라네즈", words: ["라네즈", "laneige"]),
    ShoppingBrand("esteeLauder", "에스티로더", words: ["에스티로더", "esteelauder", "estéelauder"]),
    ShoppingBrand("lancome", "랑콤", words: ["랑콤", "lancome", "lancôme"]),
    ShoppingBrand("kiehls", "키엘", words: ["키엘", "kiehls"]),
    ShoppingBrand("joMalone", "조말론", words: ["조말론", "jomalone"]),
    ShoppingBrand("clio", "클리오", words: ["클리오"], lines: ["clio"]),
    ShoppingBrand("apple", "애플", lines: ["애플", "apple"]),
    ShoppingBrand("samsung", "삼성", words: ["삼성전자", "samsung"], lines: ["삼성"]),
    ShoppingBrand("lg", "LG전자", words: ["lg전자"], lines: ["lg"]),
    ShoppingBrand("sony", "소니", words: ["소니", "sony"]),
    ShoppingBrand("dyson", "다이슨", words: ["다이슨", "dyson"]),
    ShoppingBrand("logitech", "로지텍", words: ["로지텍", "logitech"]),
    ShoppingBrand("bose", "보스", lines: ["보스", "bose"]),
    ShoppingBrand("xiaomi", "샤오미", words: ["샤오미", "xiaomi"]),
    ShoppingBrand("nintendo", "닌텐도", words: ["닌텐도", "nintendo"]),
    ShoppingBrand("lego", "레고", words: ["lego"], lines: ["레고"]),
    ShoppingBrand("philips", "필립스", words: ["philips"], lines: ["필립스"]),
    ShoppingBrand("balmuda", "발뮤다", words: ["발뮤다", "balmuda"]),
    ShoppingBrand("ikea", "이케아", words: ["이케아", "ikea"]),
  ]
}
