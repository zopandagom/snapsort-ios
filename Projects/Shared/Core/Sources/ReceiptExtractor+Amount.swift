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

  /// 금액 토큰 하나. 수는 자릿수 문자열로 두어 통화를 정한 뒤 정확하게 최소 단위로 바꾼다.
  struct AmountToken: Hashable {
    /// 천 단위 구분을 뺀 정수부 숫자.
    let integerDigits: String
    /// 소수부 숫자(없으면 빈 문자열).
    let fractionDigits: String
    let mark: CurrencyMark?
    /// 붙은 부호("-9,000"), 괄호("(9,000)"), 뒤 부호("9,000-").
    let isNegative: Bool
    /// 검사용 문자 배열에서의 위치.
    let range: Range<Int>
    /// 점 천 단위("1.234,56")로 읽었다. 유로에서만 유효하다(다른 통화면 "$45.205" 같은 오독을 큰 금액으로 읽게 된다).
    var usesDotGrouping = false

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
  private static let forbiddenBefore = Set<Character>([".", ",", "/", "#", "@", "$", "₩", "￦", "€", "¥", "￥"])
    .union(unsupportedCurrencySymbols)
  /// 토큰 바로 뒤에 오면 토큰이 아닌 글자(숫자·글자는 따로 본다).
  private static let forbiddenAfter: Set<Character> = ["%", "*", "×", "@", "/", "#"]
  private static let minusSigns: Set<Character> = ["-", "−"]
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

  /// `[부호][앞 통화] 수 [뒤 통화][뒤 부호]` 를 `start` 에서 읽는다. 앞뒤 경계가 맞지 않으면 nil.
  private static func token(startingAt start: Int, in characters: [Character], hasHangul: Bool) -> AmountToken? {
    guard var parts = self.tokenHead(startingAt: start, in: characters, hasHangul: hasHangul) else { return nil }
    if parts.mark != nil, parts.position < characters.count, characters[parts.position] == " " {
      parts.position += 1
    }
    guard parts.position < characters.count, characters[parts.position].isNumber,
          let number = self.number(at: parts.position, in: characters)
    else { return nil }
    parts.position = number.end
    guard self.readTokenTail(in: characters, into: &parts) else { return nil }
    // 통화 표시 없는 두 자리 이하 정수는 수량·번호다("합계 3", "TOTAL 2").
    if parts.mark == nil, !number.hasSeparator, number.fraction.isEmpty, (Int(number.integer) ?? 100) < 100 {
      return nil
    }
    return AmountToken(
      integerDigits: number.integer,
      fractionDigits: number.fraction,
      mark: parts.mark,
      isNegative: parts.isNegative,
      range: start ..< parts.position,
      usesDotGrouping: number.usesDotGrouping
    )
  }

  /// 읽는 중인 토큰의 위치와 부호·괄호·통화 표시.
  private struct TokenParts {
    var position: Int
    var mark: CurrencyMark?
    var isNegative = false
    var isParenthesized = false
  }

  /// 토큰 앞부분: 앞 경계, 붙은 부호나 여는 괄호, 앞 통화 표시.
  private static func tokenHead(startingAt start: Int, in characters: [Character], hasHangul: Bool) -> TokenParts? {
    if start > 0 {
      let previous = characters[start - 1]
      if characters[start] == "$", previous.isASCII, previous.isLetter {
        // "CA$12.00" 처럼 영문자가 붙은 달러는 지원하지 않는 통화 표시다("US$" 는 'U' 에서 시작해 읽는다).
        return TokenParts(position: start + 1, mark: .unsupported)
      }
      if previous.isLetter || previous.isNumber || self.forbiddenBefore.contains(previous) {
        return nil
      }
    }
    var parts = TokenParts(position: start)
    if characters[start] == "(" {
      parts.isParenthesized = true
      parts.position += 1
    } else if self.minusSigns.contains(characters[start]) {
      // 부호는 붙어 있을 때만이다. "합계 - 9,000" 의 떨어진 줄표는 구분자다.
      guard start + 1 < characters.count, !characters[start + 1].isWhitespace else { return nil }
      parts.isNegative = true
      parts.position += 1
    }
    if let (length, mark) = self.leadingMark(at: parts.position, in: characters, hasHangul: hasHangul) {
      parts.mark = mark
      parts.position += length
    }
    return parts
  }

  /// 수 뒤: 뒤 통화 표시, 뒤 부호("9,000-"), 닫는 괄호, 뒤 경계. 경계가 맞지 않으면 false.
  private static func readTokenTail(in characters: [Character], into parts: inout TokenParts) -> Bool {
    if parts.mark == nil, let (length, mark) = self.trailingMark(at: parts.position, in: characters) {
      parts.mark = mark
      parts.position += length
    }
    let position = parts.position
    if position < characters.count, self.minusSigns.contains(characters[position]),
       !(position + 1 < characters.count && characters[position + 1].isNumber)
    {
      parts.isNegative = true
      parts.position += 1
    }
    if parts.isParenthesized {
      guard parts.position < characters.count, characters[parts.position] == ")" else { return false }
      parts.isNegative = true
      parts.position += 1
    }
    guard parts.position < characters.count else { return true }
    let next = characters[parts.position]
    let continuesNumber = (next == "." || next == ",") && parts.position + 1 < characters.count
      && characters[parts.position + 1].isNumber
    return !(next.isLetter || next.isNumber || self.forbiddenAfter.contains(next) || continuesNumber)
  }

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
  private static func trailingMark(at position: Int, in characters: [Character]) -> (Int, CurrencyMark)? {
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

  /// 대소문자를 무시하고 `text` 가 `position` 에서 시작하는지.
  private static func matches(_ text: String, at position: Int, in characters: [Character]) -> Bool {
    guard position >= 0, position + text.count <= characters.count else { return false }
    return zip(text, characters[position...]).allSatisfy { $0.lowercased() == $1.lowercased() }
  }

  /// 읽은 수. 정수부는 천 단위 구분을 뺀 숫자다.
  private struct ParsedNumber {
    let integer: String
    let fraction: String
    let hasSeparator: Bool
    var usesDotGrouping = false
    let end: Int
  }

  /// 수: (a) 쉼표 천 단위, (b) 점 천 단위, (c) 구분 없음(정수부 7자리까지) 순서로 처음 맞는 것.
  /// (b) 는 통화를 정한 뒤 유로일 때만 금액이 된다(`AmountToken.usesDotGrouping`).
  private static func number(at position: Int, in characters: [Character]) -> ParsedNumber? {
    let rest = String(characters[position...])
    if let match = rest.prefixMatch(of: #/(\d{1,3}(?:,\d{3})+)(?:\.(\d{1,2}))?/#) {
      return ParsedNumber(
        integer: match.1.filter(\.isNumber),
        fraction: String(match.2 ?? ""),
        hasSeparator: true,
        end: position + match.0.count
      )
    }
    if let match = rest.prefixMatch(of: #/(\d{1,3}(?:\.\d{3})+)(?:,(\d{1,2}))?/#) {
      return ParsedNumber(
        integer: match.1.filter(\.isNumber),
        fraction: String(match.2 ?? ""),
        hasSeparator: true,
        usesDotGrouping: true,
        end: position + match.0.count
      )
    }
    if let match = rest.prefixMatch(of: #/(\d{1,7})(?:[.,](\d{1,2}))?/#) {
      return ParsedNumber(
        integer: String(match.1),
        fraction: String(match.2 ?? ""),
        hasSeparator: false,
        end: position + match.0.count
      )
    }
    return nil
  }
}
