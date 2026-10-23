import Foundation

// 영수증 금액 토큰 한 개를 읽는 문법: 앞 부호·앞 통화·수·뒤 통화·끝 표시와 앞뒤 경계 (docs/ARCHITECTURE.md §4 영수증 추출).
extension ReceiptExtractor {
  /// `[부호][앞 통화][부호] 수 [뒤 통화][끝 표시]` 를 `start` 에서 읽는다. 앞뒤 경계가 맞지 않으면 nil.
  static func token(startingAt start: Int, in characters: [Character], hasHangul: Bool) -> AmountToken? {
    guard var parts = self.tokenHead(startingAt: start, in: characters, hasHangul: hasHangul),
          parts.position < characters.count, characters[parts.position].isNumber,
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
      sign: parts.sign,
      range: start ..< parts.position,
      usesDotGrouping: number.usesDotGrouping,
      hasSeparator: number.hasSeparator,
      hasLeadingMark: parts.hasLeadingMark
    )
  }

  /// 읽는 중인 토큰의 위치와 부호·괄호·통화 표시.
  private struct TokenParts {
    var position: Int
    var mark: CurrencyMark?
    var sign: AmountSign?
    var isParenthesized = false
    var hasLeadingMark = false
  }

  /// 토큰 앞부분: 앞 경계, 앞 부호(마이너스·△▲·负)나 여는 괄호, 앞 표시 金·금, 앞 통화 표시와 그 뒤 마이너스("¥-1,100").
  /// 부호는 수에 공백 없이 붙어야 하고, 통화 표시와 부호 사이·△▲ 와 통화 표시 사이는 공백 하나까지 받는다.
  private static func tokenHead(startingAt start: Int, in characters: [Character], hasHangul: Bool) -> TokenParts? {
    if start > 0 {
      let previous = characters[start - 1]
      if characters[start] == "$", previous.isASCII, previous.isLetter {
        // "CA$12.00" 처럼 영문자가 붙은 달러는 지원하지 않는 통화 표시다("US$" 는 'U' 에서 시작해 읽는다).
        return TokenParts(position: start + 1, mark: .unsupported, hasLeadingMark: true)
      }
      if previous.isLetter || previous.isNumber || self.forbiddenBefore.contains(previous) {
        return nil
      }
    }
    guard var parts = self.leadingSign(at: start, in: characters, hasHangul: hasHangul) else { return nil }
    if self.amountPrefixes.contains(characters[start]) {
      return parts
    }
    if let (length, mark) = self.leadingMark(at: parts.position, in: characters, hasHangul: hasHangul) {
      parts.mark = mark
      parts.hasLeadingMark = true
      parts.position += length
      if self.character(at: parts.position, in: characters) == " " {
        parts.position += 1
      }
      // 통화 표시 뒤 마이너스("¥-1,100"·"$ -12.50")도 수에 붙어 있으면 음수다.
      if let minus = self.character(at: parts.position, in: characters), self.minusSigns.contains(minus),
         self.character(at: parts.position + 1, in: characters)?.isNumber == true
      {
        parts.sign = .explicit
        parts.position += 1
      }
    }
    return parts
  }

  /// `start` 의 앞 부호·여는 괄호·앞 표시. 부호가 수(나 △▲ 면 통화 표시)에 붙지 않았으면 nil.
  private static func leadingSign(at start: Int, in characters: [Character], hasHangul: Bool) -> TokenParts? {
    let next = self.character(at: start + 1, in: characters)
    var parts = TokenParts(position: start + 1)
    switch characters[start] {
    case "(":
      parts.isParenthesized = true
    case let first where self.minusSigns.contains(first):
      // 부호는 붙어 있을 때만이다. "합계 - 9,000" 의 떨어진 줄표는 구분자다.
      guard let next, !next.isWhitespace else { return nil }
      parts.sign = .explicit
    case "△", "▲":
      guard let position = self.trianglePosition(after: start, in: characters, hasHangul: hasHangul) else { return nil }
      parts.position = position
      parts.sign = .triangle
    case "负":
      guard next.map({ $0.isNumber || $0 == "¥" || $0 == "￥" }) == true else { return nil }
      parts.sign = .chineseMinus
    case let first where self.amountPrefixes.contains(first):
      guard next?.isNumber == true else { return nil }
    default:
      return TokenParts(position: start)
    }
    return parts
  }

  /// △·▲ 뒤에서 수나 앞 통화 표시가 시작하는 위치. 수에 붙었거나 앞 통화 표시에 공백 0~1 로 붙었을 때만이다
  /// ("△1,100"·"△ ¥1,100". "△ 1,100" 은 부호가 아니다).
  private static func trianglePosition(after start: Int, in characters: [Character], hasHangul: Bool) -> Int? {
    if self.character(at: start + 1, in: characters)?.isNumber == true {
      return start + 1
    }
    let markStart = self.character(at: start + 1, in: characters) == " " ? start + 2 : start + 1
    return self.leadingMark(at: markStart, in: characters, hasHangul: hasHangul) == nil ? nil : markStart
  }

  /// 범위 밖이면 nil 인 글자.
  private static func character(at index: Int, in characters: [Character]) -> Character? {
    index < characters.count ? characters[index] : nil
  }

  /// 수 뒤: 뒤 통화 표시(앞 표시와 함께 쓰면 같은 통화일 때만 그 통화), 금액 끝 표시(也·整·정), 끝 줄표, 닫는 괄호, 뒤 경계.
  /// 경계가 맞지 않으면 false.
  private static func readTokenTail(in characters: [Character], into parts: inout TokenParts) -> Bool {
    if let (length, trailing) = self.trailingMark(at: parts.position, in: characters) {
      parts.mark = parts.mark.map { self.combined($0, trailing) } ?? trailing
      parts.position += length
      if parts.position < characters.count, self.endMarks.contains(characters[parts.position]) {
        parts.position += 1
      }
    }
    let position = parts.position
    if position < characters.count, self.trailingDashes.contains(characters[position]),
       !(position + 1 < characters.count && characters[position + 1].isNumber)
    {
      parts.sign = parts.sign ?? .trailingDash
      parts.position += 1
    }
    if parts.isParenthesized {
      guard parts.position < characters.count, characters[parts.position] == ")" else { return false }
      parts.sign = .explicit
      parts.position += 1
    }
    guard parts.position < characters.count else { return true }
    let next = characters[parts.position]
    let continuesNumber = (next == "." || next == ",") && parts.position + 1 < characters.count
      && characters[parts.position + 1].isNumber
    return !(next.isLetter || next.isNumber || self.forbiddenAfter.contains(next) || continuesNumber)
  }

  /// 앞뒤 통화 표시를 함께 쓴 토큰의 통화("¥1,100円" 은 엔, "¥88元" 은 위안). 어긋나면 지원하지 않는 통화로 본다.
  private static func combined(_ leading: CurrencyMark, _ trailing: CurrencyMark) -> CurrencyMark {
    switch (leading, trailing) {
    case (.yen, .currency(.jpy)), (.yen, .currency(.cny)): trailing
    case let (lhs, rhs) where lhs == rhs: lhs
    default: .unsupported
    }
  }

  /// 대소문자를 무시하고 `text` 가 `position` 에서 시작하는지.
  static func matches(_ text: String, at position: Int, in characters: [Character]) -> Bool {
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
    // 좁은 공백 천 단위("1 234,56")와 아포스트로피 천 단위("1'234.50")는 그 관례로만 쓰여 한 수로 읽는다.
    if let match = rest.prefixMatch(of: #/(\d{1,3}(?:[\u{00A0}\u{202F}\u{2009}]\d{3})+)(?:[.,](\d{1,2}))?/#) {
      return ParsedNumber(
        integer: match.1.filter(\.isNumber),
        fraction: String(match.2 ?? ""),
        hasSeparator: true,
        end: position + match.0.count
      )
    }
    if let match = rest.prefixMatch(of: #/(\d{1,3}(?:['’]\d{3})+)(?:\.(\d{1,2}))?/#) {
      return ParsedNumber(
        integer: match.1.filter(\.isNumber),
        fraction: String(match.2 ?? ""),
        hasSeparator: true,
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
