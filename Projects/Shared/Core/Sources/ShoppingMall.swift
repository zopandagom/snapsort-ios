/// 쇼핑몰 닫힌 목록의 한 몰 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). `id` 는 저장 키라 바꾸지 않는다.
/// 이름·도메인·서비스 이름은 지식으로 적은 값이고 실행해 확인하지 않았다. 목록을 바꾸면 `CaptureGroupExtractor.rulesVersion` 을 올린다.
public struct ShoppingMall: Sendable, Hashable, Identifiable {
  public let id: String
  /// 섹션 이름(표의 값. OCR 텍스트가 아니다).
  public let name: String
  /// 낱말 대조 별칭(정규화한 꼴: 소문자, 공백 없음). 이름·영문·그 몰에만 있는 서비스 이름.
  let words: [String]
  /// 줄 대조 별칭(정규화한 줄 전체가 같을 때만). 일반 낱말이기도 한 이름.
  let lines: [String]
  /// 도메인(소문자). 낱말의 호스트가 이것이거나 ".이것" 으로 끝나면 맞다.
  let domains: [String]

  /// 표에서 찾는다. 없으면 nil.
  public init?(id: String) {
    guard let mall = Self.all.first(where: { $0.id == id }) else { return nil }
    self = mall
  }

  private init(_ id: String, _ name: String, words: [String], lines: [String] = [], domains: [String]) {
    self.id = id
    self.name = name
    self.words = words
    self.lines = lines
    self.domains = domains
  }

  /// 표. 넣지 않은 것: "스마일배송"(G마켓·옥션 공용), "네이버"·"네이버페이"·"카카오페이"·"토스"(여러 몰의 결제 수단·검색),
  /// "알리"(짧은 말), "크림"(일반 낱말), "새벽배송"·"무료배송"(일반 말), "쿠팡이츠"(배달 앱, 같음 대조라 쿠팡이 아니다).
  public static let all: [ShoppingMall] = [
    ShoppingMall(
      "coupang", "쿠팡",
      words: ["쿠팡", "coupang", "로켓배송", "로켓프레시", "로켓와우", "로켓직구"], domains: ["coupang.com"]
    ),
    ShoppingMall(
      "naverShopping", "네이버쇼핑",
      words: ["네이버쇼핑", "네이버플러스스토어", "스마트스토어", "smartstore"],
      domains: ["shopping.naver.com", "smartstore.naver.com", "brand.naver.com"]
    ),
    ShoppingMall("elevenStreet", "11번가", words: ["11번가", "11st", "슈팅배송"], domains: ["11st.co.kr"]),
    ShoppingMall("gmarket", "G마켓", words: ["g마켓", "지마켓", "gmarket"], domains: ["gmarket.co.kr"]),
    ShoppingMall("auction", "옥션", words: ["옥션"], lines: ["auction"], domains: ["auction.co.kr"]),
    ShoppingMall(
      "ssg", "SSG.COM",
      words: ["ssg.com", "ssg닷컴", "쓱닷컴", "쓱배송"], lines: ["ssg"], domains: ["ssg.com"]
    ),
    ShoppingMall("lotteOn", "롯데온", words: ["롯데온", "lotteon"], domains: ["lotteon.com"]),
    ShoppingMall("kurly", "컬리", words: ["컬리", "마켓컬리", "kurly", "샛별배송"], domains: ["kurly.com"]),
    ShoppingMall(
      "oliveYoung", "올리브영", words: ["올리브영", "oliveyoung", "오늘드림"], domains: ["oliveyoung.co.kr"]
    ),
    ShoppingMall("musinsa", "무신사", words: ["무신사", "musinsa"], domains: ["musinsa.com"]),
    ShoppingMall("twentyNineCM", "29CM", words: ["29cm"], domains: ["29cm.co.kr"]),
    ShoppingMall("wConcept", "W컨셉", words: ["w컨셉", "wconcept"], domains: ["wconcept.co.kr"]),
    ShoppingMall("zigzag", "지그재그", words: ["직진배송"], lines: ["지그재그", "zigzag"], domains: ["zigzag.kr"]),
    ShoppingMall("ably", "에이블리", words: ["에이블리", "ably"], domains: ["a-bly.com"]),
    ShoppingMall("ohouse", "오늘의집", words: ["오늘의집"], domains: ["ohou.se"]),
    ShoppingMall(
      "aliExpress", "알리익스프레스", words: ["알리익스프레스", "aliexpress"], domains: ["aliexpress.com"]
    ),
    ShoppingMall("temu", "테무", words: ["테무", "temu"], domains: ["temu.com"]),
    ShoppingMall("shein", "쉬인", words: ["쉬인", "shein"], domains: ["shein.com"]),
    ShoppingMall("amazon", "아마존", words: ["아마존", "amazon"], domains: ["amazon.com", "amazon.co.jp"]),
    ShoppingMall("tmon", "티몬", words: ["티몬", "tmon"], domains: ["tmon.co.kr"]),
    ShoppingMall("wemakeprice", "위메프", words: ["위메프", "wemakeprice"], domains: ["wemakeprice.com"]),
    ShoppingMall("interpark", "인터파크", words: ["인터파크", "interpark"], domains: ["interpark.com"]),
    ShoppingMall("kream", "KREAM", words: ["kream"], domains: ["kream.co.kr"]),
    ShoppingMall("bunjang", "번개장터", words: ["번개장터", "bunjang"], domains: ["bunjang.co.kr"]),
    ShoppingMall("daangn", "당근", words: ["당근마켓", "daangn"], lines: ["당근"], domains: ["daangn.com"]),
    ShoppingMall("gsShop", "GS SHOP", words: ["gsshop", "gs샵"], domains: ["gsshop.com"]),
    ShoppingMall("cjOnStyle", "CJ온스타일", words: ["cj온스타일", "cjonstyle"], domains: ["cjonstyle.com"]),
    ShoppingMall(
      "hmall", "현대Hmall", words: ["hmall", "현대hmall", "현대홈쇼핑"], domains: ["hmall.com"]
    ),
  ]
}
