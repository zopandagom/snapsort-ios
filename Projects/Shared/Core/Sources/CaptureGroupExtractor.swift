/// 쇼핑·대화·지도 캡처의 묶음 값 추출 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). 저장된 OCR 줄을 기기 안 닫힌 목록
/// (쇼핑몰·브랜드·대화 앱 문구·한국 행정구역)과 대조하는 순수 함수다. 날짜를 쓰지 않고 줄 밖의 정보도 쓰지 않는다.
/// "틀린 값보다 빈 값": 애매하면 값을 정하지 않는다. 같음 대조라 한국어 조사가 붙은 낱말("쿠팡에서")은 받지 않는다(알려진 한계).
/// 줄의 텍스트는 목록 대조에만 쓰고 결과에는 목록의 값만 담는다. 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public enum CaptureGroupExtractor {
  /// 규칙·닫힌 목록을 바꿔 같은 줄에서 다른 값이 나올 수 있으면 올린다(목록에 몰·브랜드·문구·행정구역을 더하거나 빼는 것 포함).
  /// 저장된 값이 지금 버전과 다르면 인덱서가 저장된 줄로 다시 추출한다.
  public static let rulesVersion = 1

  /// 묶음 값을 찾는 카테고리.
  public static let categories: Set<ImageCategory> = [.shopping, .chat, .map]

  /// 들어 있는 카테고리의 필드만 찾는다(`CaptureGroups.restricted(to:)` 와 같은 결과).
  public static func extract(from lines: [RecognizedTextLine], categories: Set<ImageCategory>) -> CaptureGroups {
    let texts = lines.map(\.text)
    let isShopping = categories.contains(.shopping)
    return CaptureGroups(
      mall: isShopping ? Self.mall(in: texts) : nil,
      brand: isShopping ? Self.brand(in: texts) : nil,
      chatApp: categories.contains(.chat) ? Self.chatApp(in: texts) : nil,
      regions: categories.contains(.map) ? Self.regions(in: texts) : []
    )
  }

  // MARK: - 대화 앱

  /// 줄 전체가 앱의 고유 문구와 같은 앱. 서로 다른 앱이 정확히 하나일 때만 그 앱이다.
  static func chatApp(in texts: [String]) -> ChatApp? {
    let lines = Set(texts.map(Self.normalizedLine))
    let apps = ChatApp.allCases.filter { app in app.signatures.contains { lines.contains($0) } }
    return apps.count == 1 ? apps[0] : nil
  }

  // MARK: - 쇼핑몰·브랜드

  /// 서로 다른 몰이 이미지 전체에서 정확히 하나일 때만 그 몰이다(가격 비교 화면처럼 둘 이상이면 nil).
  static func mall(in texts: [String]) -> ShoppingMall? {
    var found: Set<String> = []
    var result: ShoppingMall?
    for text in texts {
      let line = Self.normalizedLine(text)
      let words = Self.normalizedWords(text)
      let candidates = Self.joined(words)
      for mall in ShoppingMall.all where !found.contains(mall.id) {
        let isWord = mall.words.contains { candidates.contains($0) }
        let isLine = mall.lines.contains(line)
        let isDomain = words.contains { word in
          guard let host = Self.host(of: word) else { return false }
          return mall.domains.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
        if isWord || isLine || isDomain {
          found.insert(mall.id)
          result = mall
        }
      }
    }
    return found.count == 1 ? result : nil
  }

  /// 서로 다른 브랜드가 정확히 하나일 때만 그 브랜드다(추천 상품·랭킹 화면처럼 둘 이상이면 nil).
  /// 액세서리·호환 상품 줄(`isAccessoryLine`)은 브랜드를 찾지 않는다("닌텐도 스위치 호환 케이스").
  static func brand(in texts: [String]) -> ShoppingBrand? {
    var found: Set<String> = []
    var result: ShoppingBrand?
    for text in texts {
      let words = Self.normalizedWords(text)
      guard !Self.isAccessoryLine(text, words: words) else { continue }
      let line = Self.normalizedLine(text)
      let candidates = Self.joined(words)
      for brand in ShoppingBrand.all where !found.contains(brand.id) {
        if brand.words.contains(where: { candidates.contains($0) }) || brand.lines.contains(line) {
          found.insert(brand.id)
          result = brand
        }
      }
    }
    return found.count == 1 ? result : nil
  }

  /// 줄에 액세서리·호환 낱말이 있다. 한글은 부분 문자열(붙여 써도 "아이폰케이스"), 라틴과 한글 "스킨"·"커버"는 낱말 같음이다
  /// ("스킨케어"·"커버력"·"커버 쿠션"은 건너뛰지 않고 "폰 스킨"·"아이폰 커버"는 건너뛴다). 정품 줄("애플 정품 케이블")도 건너뛴다(빈 값 쪽).
  private static func isAccessoryLine(_ text: String, words: [String]) -> Bool {
    let lowercased = text.lowercased()
    if Self.accessorySubstrings.contains(where: { lowercased.contains($0) }) {
      return true
    }
    return words.contains { Self.accessoryWords.contains($0) }
  }

  private static let accessorySubstrings = [
    "호환", "전용", "케이스", "보호필름", "필름", "강화유리", "거치대", "스트랩", "밴드", "파우치", "충전기", "케이블", "어댑터", "키링",
  ]

  private static let accessoryWords: Set<String> = [
    "스킨", "커버",
    "compatible", "for", "case", "cover", "film", "protector", "holder", "stand", "strap", "band", "pouch", "charger",
    "cable", "adapter", "skin",
  ]

  // MARK: - 지도 지역

  /// 줄마다(줄을 넘어 짝짓지 않는다) 낱말 단위로 시·도+시·군·구 짝, 유일한 시·군·구, 줄 전체가 시·도 별칭인 시·도만을 모은다.
  /// 같은 시·도의 시·군·구 지역이 있으면 그 시·도만 지역은 뺀다. 서로 다른 지역이 여럿이면 모두 담는다.
  /// 시·도 이름만 낱말로 섞인 줄("제주 흑돼지"·"서울 나들이")은 시·도만으로 받지 않는다(가게·글 이름 속 지명).
  static func regions(in texts: [String]) -> Set<KoreanRegion> {
    var found: Set<KoreanRegion> = []
    for text in texts {
      let words = Self.normalizedWords(text)
      var index = 0
      while index < words.count {
        let word = words[index]
        if let province = KoreanAdministrativeDivisions.provinceAliases[word] {
          index += 1
          guard index < words.count,
                let entry = KoreanAdministrativeDivisions.entry(named: words[index], in: province)
          else { continue }
          found.insert(KoreanRegion(province: province, district: entry.city))
          index += 1
          // 같은 시로 올라가는 일반구가 이어지면 함께 건너뛴다("경기도 성남시 분당구").
          while index < words.count,
                let next = KoreanAdministrativeDivisions.entry(named: words[index], in: province),
                next.isGeneralDistrict, next.city == entry.city
          {
            index += 1
          }
          continue
        }
        let candidates = KoreanAdministrativeDivisions.regions(named: word)
        if candidates.count == 1, !KoreanAdministrativeDivisions.ambiguousStandaloneDistricts.contains(word),
           let region = candidates.first
        {
          found.insert(region)
        }
        index += 1
      }
      let line = Self.normalizedLine(text)
      if KoreanAdministrativeDivisions.standaloneProvinceAliases.contains(line),
         let province = KoreanAdministrativeDivisions.provinceAliases[line]
      {
        found.insert(KoreanRegion(province: province, district: nil))
      }
    }
    let provincesWithDistrict = Set(found.filter { $0.district != nil }.map(\.province))
    return found.filter { $0.district != nil || !provincesWithDistrict.contains($0.province) }
  }

  // MARK: - 정규화

  /// 낱말: 줄을 공백으로 나눈 조각을 소문자로 바꾸고, 아포스트로피(`'`·`’`)를 지우고, 앞뒤의 글자·숫자·`&` 밖 문자
  /// (괄호·`#`·`,`·`:`·`·`·따옴표·`!`·`?`·`.`·`「」` 등)를 지운다. 가운데 글자는 둔다(`ssg.com`, `h&m`, `m.coupang.com/vp/1`).
  /// 비교는 Swift `String` 같음(정규 동등)이라 NFC 차이를 흡수한다.
  static func normalizedWords(_ text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).compactMap { piece in
      let word = Self.trimmed(String(piece).lowercased().filter { $0 != "'" && $0 != "’" })
      return word.isEmpty ? nil : word
    }
  }

  /// 줄: 공백을 모두 지우고 소문자로 바꾼 뒤 앞뒤 기호(끝의 `…`·`...` 포함)를 지운 것.
  static func normalizedLine(_ text: String) -> String {
    self.trimmed(String(text.lowercased().filter { !$0.isWhitespace }))
  }

  /// 이웃한 2·3 낱말을 공백 없이 이은 것("new"+"balance", "the"+"north"+"face")과 낱말 자체.
  private static func joined(_ words: [String]) -> Set<String> {
    var result = Set(words)
    for size in 2 ... 3 where words.count >= size {
      for start in 0 ... (words.count - size) {
        result.insert(words[start ..< start + size].joined())
      }
    }
    return result
  }

  /// `http://`·`https://` 를 떼고 첫 `/`·`?` 앞까지를 호스트로 본 것. 점이 없으면 호스트가 아니다.
  private static func host(of word: String) -> String? {
    var rest = Substring(word)
    for scheme in ["https://", "http://"] where rest.hasPrefix(scheme) {
      rest = rest.dropFirst(scheme.count)
    }
    let host = rest.prefix { $0 != "/" && $0 != "?" }
    return host.contains(".") ? String(host) : nil
  }

  private static func trimmed(_ text: String) -> String {
    let isKept: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "&" }
    guard let start = text.firstIndex(where: isKept), let end = text.lastIndex(where: isKept) else { return "" }
    return String(text[start ... end])
  }
}
