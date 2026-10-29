/// 라벨 없는 기프티콘의 교환처로 보는 브랜드 닫힌 목록 (docs/ARCHITECTURE.md §4 기프티콘 추출).
/// 이름은 지식으로 적은 값이고 실행해 확인하지 않았다. 목록을 바꾸면 `GifticonExtractor.rulesVersion` 을 올린다.
/// 기프티콘을 파는 곳(선물하기·결제 앱)은 교환처가 아니라 넣지 않는다. 표는 `ClassificationRules` 키워드 표와 따로 둔다
/// (`scripts/mask-samples.py` 는 그 표만 읽는다).
enum GifticonBrand {
  /// 브랜드마다 별칭(정규화한 꼴: 소문자, 공백 없음). 같은 배열의 별칭은 같은 교환처다("emart"·"신세계이마트").
  /// 넣지 않은 것: "카카오톡"·"네이버"·"기프티쇼"(파는 곳), "편의점"·"카페"(일반 낱말).
  static let all: [[String]] = [
    ["스타벅스", "starbucks"],
    ["투썸플레이스", "투썸", "atwosomeplace", "twosomeplace"],
    ["이디야커피", "이디야", "ediya", "ediyacoffee"],
    ["메가mgc커피", "메가커피", "megacoffee", "megamgccoffee"],
    ["컴포즈커피", "composecoffee"],
    ["빽다방"],
    ["파스쿠찌", "pascucci"],
    ["할리스", "할리스커피", "hollys", "hollyscoffee"],
    ["커피빈", "coffeebean", "thecoffeebean"],
    ["폴바셋", "paulbassett"],
    ["공차", "gongcha"],
    ["배스킨라빈스", "baskinrobbins"],
    ["던킨", "던킨도너츠", "dunkin", "dunkindonuts"],
    ["파리바게뜨", "parisbaguette"],
    ["뚜레쥬르", "touslesjours"],
    ["설빙"],
    ["맥도날드", "mcdonalds", "mcdonald's"],
    ["버거킹", "burgerking"],
    ["롯데리아", "lotteria"],
    ["kfc"],
    ["맘스터치", "momstouch"],
    ["서브웨이", "subway"],
    ["bbq", "비비큐"],
    ["bhc"],
    ["교촌치킨", "교촌"],
    ["굽네치킨", "굽네"],
    ["도미노피자", "dominos", "domino's"],
    ["피자헛", "pizzahut"],
    ["cu"],
    ["gs25"],
    ["세븐일레븐", "7-eleven", "7eleven"],
    ["이마트24", "emart24"],
    ["이마트", "emart", "신세계이마트"],
    ["신세계백화점", "신세계"],
    ["롯데마트"],
    ["홈플러스", "homeplus"],
    ["올리브영", "oliveyoung"],
    ["다이소", "daiso"],
    ["cgv"],
    ["메가박스", "megabox"],
    ["롯데시네마", "lottecinema"],
    ["현대백화점"],
    ["롯데백화점"],
    ["교보문고"],
  ]

  /// 정규화한 별칭이 든 브랜드의 위치(같은 교환처인지 견주는 데 쓴다). 목록에 없으면 nil.
  static func index(of key: String) -> Int? {
    self.indexByAlias[key]
  }

  private static let indexByAlias: [String: Int] = Dictionary(
    all.enumerated().flatMap { index, aliases in aliases.map { ($0, index) } },
    uniquingKeysWith: { first, _ in first }
  )
}
