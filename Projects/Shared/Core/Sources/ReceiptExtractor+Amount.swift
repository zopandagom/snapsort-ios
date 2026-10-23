import Foundation

// 영수증 금액 토큰·번호 가리기·통화 판정 (docs/ARCHITECTURE.md §4 영수증 추출).
extension ReceiptExtractor {
  /// 금액 토큰에 붙은 통화 표시.
  enum CurrencyMark: Hashable {
    case currency(ReceiptCurrency)
    /// `¥`·`￥`. 엔과 위안이 같은 기호라 영수증의 다른 표시로 정한다(`yenCurrency`).
    case yen
    /// 영문자가 붙은 달러("CA$"·"A$"·"HK$" 등). 지원하지 않는 통화다.
    case unsupported
  }

  /// 음수 표시의 종류. 나라마다 관례가 달라 통화를 정한 뒤 음수인지 정한다.
  enum AmountSign: Hashable {
    /// 앞 마이너스("-9,000"·"¥-1,100")와 괄호("(9,000)"). 통화와 무관하게 음수다.
    case explicit
    /// 끝 줄표("9,000-"·"¥1,100-"·"1,100ー"). 원·달러·유로는 음수, 엔·위안·통화 모름이면 금액 끝 표시다.
    case trailingDash
    /// 일본식 앞 △·▲. 엔일 때만 음수다(한국 앱의 "▲ 1,000" 증가 표시와 섞이지 않게).
    case triangle
    /// 중국식 앞 负. 위안일 때만 음수다.
    case chineseMinus
  }

  /// 금액 토큰 하나. 수는 자릿수 문자열로 두어 통화를 정한 뒤 정확하게 최소 단위로 바꾼다.
  struct AmountToken: Hashable {
    /// 천 단위 구분을 뺀 정수부 숫자.
    let integerDigits: String
    /// 소수부 숫자(없으면 빈 문자열).
    let fractionDigits: String
    let mark: CurrencyMark?
    /// 음수 표시. 통화를 정한 뒤 음수인지 정한다(`isNegative(in:)`).
    let sign: AmountSign?
    /// 검사용 문자 배열에서의 위치.
    let range: Range<Int>
    /// 점 천 단위("1.234,56")로 읽었다. 유로에서만 유효하다(다른 통화면 "$45.205" 같은 오독을 큰 금액으로 읽게 된다).
    var usesDotGrouping = false
    /// 천 단위 구분(쉼표·점·좁은 공백·아포스트로피)이 있다.
    var hasSeparator = false
    /// 통화 표시가 수 앞에 있다("¥450"). 일반 공백 천 단위 꼴 판정에서 앞 수를 수량으로 본다.
    var hasLeadingMark = false

    /// 정한 통화에서 음수인지.
    func isNegative(in currency: ReceiptCurrency?) -> Bool {
      switch self.sign {
      case .explicit: true
      case .trailingDash: currency.map { [.krw, .usd, .eur].contains($0) } ?? false
      case .triangle: currency == .jpy
      case .chineseMinus: currency == .cny
      case nil: false
      }
    }

    /// 0 보다 큰지(숫자 중 0 이 아닌 것이 있는지).
    var isPositive: Bool {
      (self.integerDigits + self.fractionDigits).contains { $0 != "0" }
    }

    /// 통화와 무관하게 같은 수인지 비교하는 값(앞쪽 0·뒤쪽 소수 0 을 뺀 자릿수).
    var numberKey: String {
      let integer = self.integerDigits.drop { $0 == "0" }
      let fraction = self.fractionDigits.reversed().drop { $0 == "0" }
      return "\(integer).\(String(fraction.reversed()))"
    }

    /// 통화 자릿수로 바꾼 최소 단위. 자릿수를 넘는 0 아닌 소수, 넘침, 상한 초과면 nil.
    func amount(in currency: ReceiptCurrency) -> ReceiptAmount? {
      guard !self.usesDotGrouping || currency == .eur else { return nil }
      let digits = currency.minorUnitDigits
      var fraction = self.fractionDigits
      if fraction.count > digits {
        guard fraction.dropFirst(digits).allSatisfy({ $0 == "0" }) else { return nil }
        fraction = String(fraction.prefix(digits))
      }
      fraction += String(repeating: "0", count: digits - fraction.count)
      var value = 0
      for character in self.integerDigits + fraction {
        guard let digit = character.wholeNumberValue else { return nil }
        let (multiplied, overflow) = value.multipliedReportingOverflow(by: 10)
        let (added, addOverflow) = multiplied.addingReportingOverflow(digit)
        guard !overflow, !addOverflow else { return nil }
        value = added
      }
      return ReceiptAmount(minorUnits: value, currency: currency)
    }
  }

  /// 금액이 아닌 번호(날짜·시각·사업자번호·전화번호·카드번호·백분율)를 공백으로 가린 검사용 문자 배열. 위치는 원문과 같다.
  static func masked(_ text: String) -> [Character] {
    var characters = Array(text)
    for range in self.numberRanges(in: text) {
      for index in range {
        characters[index] = " "
      }
    }
    return characters
  }

  /// 번호 패턴(`maskPatterns`)에 맞는 위치. 가게 위쪽 줄의 번호 줄 판정도 쓴다.
  static func numberRanges(in text: String) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    for (pattern, needsCardCheck) in self.maskPatterns {
      for match in text.matches(of: pattern) {
        let found = text[match.range]
        if needsCardCheck, !found.contains("*"), found.count(where: \.isNumber) < 15 {
          continue
        }
        ranges.append(
          text.distance(from: text.startIndex, to: match.range.lowerBound) ..< text.distance(
            from: text.startIndex,
            to: match.range.upperBound
          )
        )
      }
    }
    return ranges
  }

  /// 날짜·시각 패턴만(가게 위쪽 줄의 본문 줄 판정).
  static func containsDateOrTime(_ text: String) -> Bool {
    self.dateTimePatterns.contains { text.contains($0) }
  }

  private static var dateTimePatterns: [Regex<Substring>] {
    [
      #/\d{2,4}[.\/\-]\d{1,2}[.\/\-]\d{1,2}/#,
      #/\d{1,4}년/#,
      #/\d{1,2}월\s?\d{1,2}일/#,
      #/(?:오전|오후|AM|PM|am|pm)?\s?\d{1,2}:\d{2}(?::\d{2})?(?:\s?(?:AM|PM|am|pm))?/#,
    ]
  }

  /// 가리는 번호 패턴. 두 번째 값이 참이면 카드번호 모양이라 `*` 가 있거나 숫자 15자 이상일 때만 가린다.
  private static var maskPatterns: [(Regex<Substring>, Bool)] {
    self.dateTimePatterns.map { ($0, false) } + [
      (#/\d{3}-\d{2}-\d{5}/#, false),
      (#/(?:\+\d{1,3}[\- ]?)?\(?\d{2,4}\)?[\- ]?\d{3,4}-\d{4}/#, false),
      (#/\d{4}[\- ]?[\d*]{2,4}[\- ]?[\d*]{2,4}[\- ]?[\d*]{2,4}/#, true),
      (#/[\d*]*(?:\d\*|\*\d)[\d*]*/#, false),
      (#/\d+(?:\.\d+)?\s?%/#, false),
    ]
  }

  /// 검사용 문자 배열에서 금액 토큰을 앞에서부터 찾는다.
  /// - Parameter hasHangul: 영수증에 한글이 있으면 수 앞의 홀로 선 `W`·`\` 를 `₩` 로 본다(OCR 이 ₩ 를 잘못 읽는 경우).
  static func amountTokens(in characters: [Character], hasHangul: Bool) -> [AmountToken] {
    var tokens: [AmountToken] = []
    var index = 0
    while index < characters.count {
      if let token = self.token(startingAt: index, in: characters, hasHangul: hasHangul) {
        tokens.append(token)
        index = token.range.upperBound
      } else {
        index += 1
      }
    }
    return tokens
  }

  /// 토큰 앞에 오면 토큰이 아닌 글자(숫자·글자는 따로 본다).
  static let forbiddenBefore = Set<Character>([".", ",", "/", "#", "@", "$", "₩", "￦", "€", "¥", "￥", "'", "’"])
    .union(unsupportedCurrencySymbols)
  /// 토큰 바로 뒤에 오면 토큰이 아닌 글자(숫자·글자는 따로 본다).
  static let forbiddenAfter: Set<Character> = ["%", "*", "×", "@", "/", "#", "'", "’"]
  static let minusSigns: Set<Character> = ["-", "−"]
  /// 끝 줄표(장음 ー·― 도 같게 본다).
  static let trailingDashes: Set<Character> = ["-", "−", "ー", "―"]
  /// 뒤 통화 바로 뒤의 금액 끝 표시("円也"·"元整"·"원정").
  static let endMarks: Set<Character> = ["也", "整", "정"]
  /// 수 바로 앞의 금액 앞 표시("金1,100円"·"금9,000원정").
  static let amountPrefixes: Set<Character> = ["金", "금"]
  /// 좁은 공백(NBSP·좁은 NBSP·얇은 공백). 천 단위 구분으로만 쓴다.
  static let narrowSpaces: Set<Character> = ["\u{00A0}", "\u{202F}", "\u{2009}"]
  /// 수 앞 통화 표시. 긴 것부터 대조한다. 지원하지 않는 통화 코드·기호는 통화 모름(`.unsupported`)이다.
  private static let leadingMarks: [(String, CurrencyMark)] = [
    ("US$", .currency(.usd)), ("KRW", .currency(.krw)), ("USD", .currency(.usd)), ("EUR", .currency(.eur)),
    ("JPY", .currency(.jpy)), ("CNY", .currency(.cny)), ("RMB", .currency(.cny)), ("₩", .currency(.krw)),
    ("￦", .currency(.krw)), ("$", .currency(.usd)), ("€", .currency(.eur)), ("¥", .yen), ("￥", .yen),
  ] + unsupportedMarks
  /// 수 뒤 통화 표시.
  private static let trailingMarks: [(String, CurrencyMark)] = [
    ("KRW", .currency(.krw)), ("USD", .currency(.usd)), ("EUR", .currency(.eur)), ("JPY", .currency(.jpy)),
    ("CNY", .currency(.cny)), ("won", .currency(.krw)), ("원", .currency(.krw)), ("円", .currency(.jpy)),
    ("元", .currency(.cny)), ("€", .currency(.eur)),
  ] + unsupportedMarks
  private static let unsupportedMarks: [(String, CurrencyMark)] = unsupportedCurrencyCodes.map { ($0, .unsupported) }
    + unsupportedCurrencySymbols.map { (String($0), .unsupported) }

  /// 수 앞 통화 표시와 그 길이. 영문 코드는 낱말 경계(뒤가 영문자가 아님)일 때만.
  static func leadingMark(
    at position: Int,
    in characters: [Character],
    hasHangul: Bool
  ) -> (Int, CurrencyMark)? {
    for (text, mark) in self.leadingMarks where self.matches(text, at: position, in: characters) {
      let end = position + text.count
      if text.last?.isLetter == true, end < characters.count, characters[end].isLetter {
        continue
      }
      return (text.count, mark)
    }
    // 한글 영수증에서만 수 바로 앞(공백 0~1)의 홀로 선 W·\ 를 ₩ 로 본다.
    if hasHangul, position < characters.count, characters[position] == "W" || characters[position] == "\\" {
      let next = position + 1
      let digit = next < characters.count && characters[next] == " " ? next + 1 : next
      if digit < characters.count, characters[digit].isNumber {
        return (1, .currency(.krw))
      }
    }
    return nil
  }

  /// 수 뒤(바로 뒤 또는 공백 하나 뒤)의 통화 표시와 공백을 포함한 길이.
  static func trailingMark(at position: Int, in characters: [Character]) -> (Int, CurrencyMark)? {
    for offset in [0, 1] {
      if offset == 1, !(position < characters.count && characters[position] == " ") {
        continue
      }
      for (text, mark) in self.trailingMarks where self.matches(text, at: position + offset, in: characters) {
        let end = position + offset + text.count
        if text.first?.isASCII == true, end < characters.count, characters[end].isLetter {
          continue
        }
        return (offset + text.count, mark)
      }
    }
    return nil
  }
}
