import Foundation

// 금액 라벨 줄 판정과 그 줄의 값 (docs/ARCHITECTURE.md §4 영수증 추출).
// 값은 라벨 뒤부터 끊는 말 앞까지에서 정한다: 금액 하나뿐인 괄호를 뺀 덧말을 지우고, 첫 금액 뒤 처음 나오는 글자 낱말 앞까지만 본다.
// 그 안의 금액이 서로 다르거나, 첫 금액과 다음 금액 사이에 할인 뒤 표시가 있으면 그 줄은 값이 갈린 것으로 둔다.
extension ReceiptExtractor {
  /// 한 라벨 줄의 값.
  enum LineValue {
    case token(AmountToken)
    /// 값이 갈렸다(첫 묶음 안의 서로 다른 금액, 할인 뒤 금액). 그 단계에서 금액 모름이 된다.
    case split
    /// 범위에 금액이 없다. 범위에 글자가 없으면(라벨·통화 표시뿐) 이웃 줄을 읽는다.
    case empty(hasLetters: Bool)
  }

  /// 라벨 줄 판정: 앞 구분 기호와 덧말을 뺀 사본에서 꼬리 말을 건너뛴 첫 낱말이 없거나, 금액 토큰으로 시작하거나,
  /// 통화 표시 낱말이어야 한다. "TOTAL SAVINGS 5.00"·"합계 수량 3"·"결제금액 안내" 는 라벨 줄이 아니다.
  /// 라벨 바로 뒤 덧말이나 첫 낱말이 세금 별도 표시("合計(税抜)"·"합계(부가세 별도)"·"TOTAL (EXCL. TAX)")면 라벨 줄이 아니다.
  static func isAmountLabelLine(_ rest: Substring, context: CurrencyContext) -> Bool {
    let leading = rest.drop(while: \.isWhitespace)
    if let open = leading.first, "([（【".contains(open),
       let close = leading.firstIndex(where: { ")]）】".contains($0) }),
       self.isTaxExcluded(leading[leading.index(after: leading.startIndex) ..< close])
    {
      return false
    }
    var judged = Substring(self.removingRemarks(rest, hasHangul: context.hasHangul)).drop(while: \.isWhitespace)
    if let first = judged.first,
       ":：|".contains(first) || first == "-" && judged.dropFirst().first?.isWhitespace != false
    {
      judged = judged.dropFirst()
    }
    let words = self.words(judged).drop { self.labelTailWords.contains(self.normalizedWord($0)) }
    guard let next = words.first else { return true }
    let normalized = self.normalizedWord(next)
    if self.isTaxExcluded(words.prefix(2).joined(separator: " "), firstWordOnly: true) {
      return false
    }
    if let first = next.first, first.isNumber || "-−(₩￦$€¥￥\\△▲".contains(first) {
      return true
    }
    return self.currencyWords.contains(normalized)
      || !self.amountTokens(in: Array(next), hasHangul: context.hasHangul).isEmpty
  }

  /// 세금 별도 표시인지. 한글·한자는 부분 문자열, 라틴은 낱말 같음이나 이어진 두 낱말("sans tva")을 붙인 것이 표의 말과 같다.
  /// - Parameter firstWordOnly: 라벨 뒤 첫 낱말 대조. 라틴은 첫 낱말이나 첫 두 낱말만 본다.
  private static func isTaxExcluded(_ text: some StringProtocol, firstWordOnly: Bool = false) -> Bool {
    let lowercased = text.lowercased()
    let words = self.words(lowercased).map(self.normalizedWord)
    let checkedCJK = firstWordOnly ? words.prefix(1).joined() : lowercased
    if self.taxExcludedWords.contains(where: { self.isCJK($0) && checkedCJK.contains($0) }) {
      return true
    }
    let pairs = zip(words, words.dropFirst()).map { $0 + $1 }
    let candidates = firstWordOnly ? Array(words.prefix(1)) + pairs.prefix(1) : words + pairs
    return candidates.contains { self.taxExcludedWords.contains($0) && !self.isCJK($0) }
  }

  /// 라벨 뒤 텍스트의 값.
  static func lineValue(_ rest: Substring, context: CurrencyContext) -> LineValue {
    // 할인 뒤 금액은 덧말을 지우기 전에 본다("결제금액 10,000 (할인후 9,000)").
    if self.hasAfterDiscount(rest, context: context) {
      return .split
    }
    let text = self.removingRemarks(rest, hasHangul: context.hasHangul)
    let characters = self.masked(text)
    let spans = self.wordSpans(in: characters)
    let cut = self.cutPosition(in: text, spans: spans, characters: characters)
    let rangeEnd = cut?.lowerBound ?? characters.count
    let tokens = self.amountTokens(in: Array(characters[..<rangeEnd]), hasHangul: context.hasHangul)
    guard let first = tokens.first else {
      let leftover = spans.filter { $0.upperBound <= rangeEnd }.map { String(characters[$0]) }
        .filter { !self.currencyWords.contains(self.normalizedWord($0)) }
      return .empty(hasLetters: leftover.joined().contains(where: \.isLetter))
    }
    // 첫 금액 뒤 처음 나오는 글자 낱말(통화 표시 낱말 제외)에서 한 번 더 끊는다. 그 뒤의 세액·받은 돈 같은 금액을 쓰지 않는다.
    let letterWord = spans.first { span in
      span.lowerBound >= first.range.upperBound && span.lowerBound < rangeEnd
        && characters[span].contains(where: \.isLetter)
        && !self.currencyWords.contains(self.normalizedWord(String(characters[span])))
    }
    let end = letterWord?.lowerBound ?? rangeEnd
    let kept = tokens.filter { $0.range.upperBound <= end }
    let distinct = Set(kept.map { "\($0.numberKey)|\(String(describing: $0.mark))" })
    guard distinct.count == 1, let last = kept.last,
          !kept.contains(where: { self.followsSmallNumber($0, in: characters) })
    else { return .split }
    return .token(kept.first { $0.sign != nil } ?? last)
  }

  /// 일반 공백 하나를 사이에 두고 1~3자리 정수 뒤에 온, 천 단위 구분 없는 3자리 정수부 토큰인지("1 234,56"·"합계 2 900").
  /// 천 단위("€1,234.56")와 수량 뒤 금액(2개, 900원)을 글자만으로 가를 수 없어 그 줄은 값이 갈린 것으로 본다.
  /// 토큰에 앞 통화 표시가 있으면("2 ¥450") 앞 수를 수량으로 보아 해당하지 않는다.
  private static func followsSmallNumber(_ token: AmountToken, in characters: [Character]) -> Bool {
    let start = token.range.lowerBound
    guard token.integerDigits.count == 3, !token.hasSeparator, !token.hasLeadingMark, token.sign == nil, start >= 2,
          characters[start - 1] == " ", characters[start - 2].isNumber
    else { return false }
    var digitStart = start - 2
    while digitStart > 0, characters[digitStart - 1].isNumber {
      digitStart -= 1
    }
    let digitCount = start - 1 - digitStart
    return digitCount <= 3 && (digitStart == 0 || characters[digitStart - 1].isWhitespace)
  }

  /// 끊는 말이 처음 나오는 자리. 한글·한자·가나 끊는 말은 어디서나 부분 문자열로("(카드할인", "포함부가세"),
  /// 라틴 끊는 말은 낱말 같음 또는 끊는 말 바로 뒤가 숫자·`:`·`：`·`=`·통화 기호인 낱말로("TAX:3.20") 찾는다("TAXI" 는 아니다).
  static func cutPosition(in text: String, spans: [Range<Int>], characters: [Character]) -> Range<Int>? {
    var found: [Range<Int>] = []
    for cut in self.cutWords where self.isCJK(cut) {
      if let range = text.range(of: cut) {
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        found.append(start ..< start + cut.count)
      }
    }
    for span in spans {
      let word = String(characters[span])
      let normalized = self.normalizedWord(word)
      let lowercased = String(word.lowercased().drop { "[(【（*#".contains($0) })
      let isCut = self.cutWords.contains { cut in
        !self.isCJK(cut) && (normalized == cut || lowercased.hasPrefix(cut) && lowercased.dropFirst(cut.count).first
          .map { $0.isNumber || ":：=₩￦$€¥￥".contains($0) } == true)
      }
      if isCut {
        found.append(span)
        break
      }
    }
    return found.min { $0.lowerBound < $1.lowerBound }
  }

  /// 이웃한 두 금액(괄호 안이어도) 사이마다 할인 뒤 표시가 있는지: 후·後·后 는 낱말 안 어디든(붙어 있어도, "쿠폰할인후"·
  /// "会員割引後"), after·net 은 낱말 같음. 다음 금액이 없으면 보지 않는다("결제금액 9,000 후불결제" 는 그대로 값이다).
  private static func hasAfterDiscount(_ rest: Substring, context: CurrencyContext) -> Bool {
    let characters = self.masked(String(rest))
    let tokens = self.amountTokens(in: characters, hasHangul: context.hasHangul)
    return zip(tokens, tokens.dropFirst()).contains { previous, next in
      let between = characters[previous.range.upperBound ..< next.range.lowerBound]
      return between.contains(where: self.afterDiscountCharacters.contains)
        || self.words(String(between)).contains { self.afterDiscountLatin.contains(self.normalizedWord($0)) }
    }
  }

  /// 괄호 덧말을 공백으로 바꾼다. 안이 금액 토큰 하나뿐인 괄호("(9,000)"·"(₩9,000)")만 남긴다(음수 괄호와 취소 근거).
  /// 숫자가 든 덧말도 지운다("(VAT포함)"·"(10%対象 ¥1,000 内消費税等 ¥80)"·"(봉사료 900)"). 닫는 괄호가 없으면 두고 첫 묶음 규칙이 막는다.
  static func removingRemarks(_ text: some StringProtocol, hasHangul: Bool) -> String {
    String(text).replacing(#/[(（\[【][^()（）\[\]【】]*[)）\]】]/#) { match in
      self.singleToken(in: String(match.output), hasHangul: hasHangul) == nil ? " " : String(match.output)
    }
  }

  /// 공백으로 나눈 낱말의 위치.
  static func wordSpans(in characters: [Character]) -> [Range<Int>] {
    var spans: [Range<Int>] = []
    var start: Int?
    for (index, character) in characters.enumerated() {
      if character.isWhitespace {
        if let begin = start {
          spans.append(begin ..< index)
        }
        start = nil
      } else if start == nil {
        start = index
      }
    }
    if let begin = start {
      spans.append(begin ..< characters.count)
    }
    return spans
  }
}
