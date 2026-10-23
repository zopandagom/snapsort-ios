import Foundation

// 영수증 통화 판정: 줄·영수증의 통화 표시와 `¥` 규칙 (docs/ARCHITECTURE.md §4 영수증 추출).
extension ReceiptExtractor {
  /// 줄에 있는 통화 표시 종류: 기호, 낱말 경계의 영문 코드, 숫자 바로 뒤(공백 0~1)의 원·円·元,
  /// 한글 영수증이면 수 앞의 홀로 선 W·\. "회원"·"직원" 의 "원" 은 숫자 뒤가 아니라 세지 않는다.
  static func currencyMarks(in text: String, hasHangul: Bool) -> Set<CurrencyMark> {
    let characters = Array(text)
    var marks: Set<CurrencyMark> = []
    var letters = ""
    for index in characters.indices {
      if let mark = self.symbolMark(at: index, in: characters, letters: letters) {
        marks.insert(mark)
      }
      if characters[index].isASCII, characters[index].isLetter {
        letters.append(characters[index])
        continue
      }
      self.codeMark(letters, endingAt: index, in: characters).map { _ = marks.insert($0) }
      letters = ""
    }
    self.codeMark(letters, endingAt: characters.count, in: characters).map { _ = marks.insert($0) }
    // 한글 영수증에서만 수 앞의 홀로 선 W·\ 를 ₩ 로 본다(토큰의 앞 통화와 같은 규칙).
    let misreadWon = hasHangul && characters.indices.contains { index in
      (characters[index] == "W" || characters[index] == "\\") && (index == 0 || !characters[index - 1].isLetter)
        && self.leadingMark(at: index, in: characters, hasHangul: true) != nil
    }
    return misreadWon ? marks.union([.currency(.krw)]) : marks
  }

  /// 한 글자 통화 기호의 표시. `$` 는 바로 앞 영문자(`letters`)가 없거나 "US" 면 달러, 그 밖은 지원하지 않는 달러다.
  /// 원·円·元 은 숫자 바로 뒤(공백 하나 뒤도, "9,000 원")일 때만.
  private static func symbolMark(at index: Int, in characters: [Character], letters: String) -> CurrencyMark? {
    switch characters[index] {
    case "₩", "￦": return .currency(.krw)
    case "€": return .currency(.eur)
    case "¥", "￥": return .yen
    case let symbol where self.unsupportedCurrencySymbols.contains(symbol): return .unsupported
    case "$": return letters.isEmpty || letters.uppercased() == "US" ? .currency(.usd) : .unsupported
    case "원", "円", "元":
      let previous = index > 0 && characters[index - 1] == " " ? index - 2 : index - 1
      guard previous >= 0, characters[previous].isNumber else { return nil }
      return .currency(characters[index] == "원" ? .krw : characters[index] == "円" ? .jpy : .cny)
    default: return nil
    }
  }

  /// 낱말 경계의 영문 코드 표시. "won" 은 영어 낱말이기도 해("WON TON HOUSE"·"You won 50 points") 숫자 바로 뒤(공백 0~1,
  /// "9,000 won")일 때만 원으로 센다. ISO 코드(USD·EUR 등)는 따로 쓰여도("Currency: USD") 통화 표시다.
  private static func codeMark(_ letters: String, endingAt end: Int, in characters: [Character]) -> CurrencyMark? {
    let code = letters.lowercased()
    guard let mark = self.codeMarks[code] else { return nil }
    guard code == "won" else { return mark }
    let start = end - letters.count
    let before = start > 0 && characters[start - 1] == " " ? start - 2 : start - 1
    return before >= 0 && characters[before].isNumber ? mark : nil
  }

  private static let codeMarks: [String: CurrencyMark] = [
    "krw": .currency(.krw), "won": .currency(.krw), "usd": .currency(.usd), "eur": .currency(.eur),
    "jpy": .currency(.jpy), "cny": .currency(.cny), "rmb": .currency(.cny),
  ].merging(unsupportedCurrencyCodes.map { ($0.lowercased(), .unsupported) }, uniquingKeysWith: { first, _ in first })

  /// 통화 판정에 쓰는 영수증 전체의 표시.
  struct CurrencyContext {
    let hasHangul: Bool
    /// `¥` 가 뜻하는 통화. 가나·円·JPY 만 있으면 엔, 숫자 바로 뒤의 元·CNY·RMB·人民币 만 있으면 위안, 둘 다 있거나 없으면 nil.
    /// 元 은 숫자 바로 뒤(공백 0~1)일 때만 위안 증거다("元取引番号"·"地元"·"販売元" 의 元 은 아니다).
    let yenCurrency: ReceiptCurrency?
    /// 영수증 전체 줄의 통화 표시 종류(`¥`·영문자 붙은 달러는 정한 통화, 모르면 nil 로 센다).
    let receiptKinds: Set<ReceiptCurrency?>

    init(texts: [String]) {
      let hasHangul = texts.contains { $0.contains(where: \.isHangul) }
      let joined = texts.joined(separator: "\n")
      let lowercased = joined.lowercased()
      let isJapanese = joined.unicodeScalars.contains { (0x3040 ... 0x30FF).contains($0.value) } || joined.contains("円")
        || lowercased.contains("jpy")
      let isChinese = joined.contains(#/\d ?元/#) || joined.contains("人民币") || lowercased.contains("cny")
        || lowercased.contains("rmb")
      self.hasHangul = hasHangul
      self.yenCurrency = isJapanese == isChinese ? nil : isJapanese ? .jpy : .cny
      var kinds: Set<ReceiptCurrency?> = []
      for text in texts {
        for mark in ReceiptExtractor.currencyMarks(in: text, hasHangul: hasHangul) {
          kinds.insert(Self.resolved(mark, yenCurrency: self.yenCurrency))
        }
      }
      self.receiptKinds = kinds
    }

    static func resolved(_ mark: CurrencyMark, yenCurrency: ReceiptCurrency?) -> ReceiptCurrency? {
      switch mark {
      case let .currency(currency): currency
      case .yen: yenCurrency
      case .unsupported: nil
      }
    }

    /// 고른 토큰의 통화: 토큰 자체의 표시 → 그 줄(`lineText`)의 표시가 한 종류 → 영수증 전체 표시가 한 종류 →
    /// 표시가 하나도 없고 한글 영수증이면 원. 그 밖은 통화 모름(nil).
    func currency(of token: AmountToken, lineText: String) -> ReceiptCurrency? {
      if let mark = token.mark {
        return Self.resolved(mark, yenCurrency: self.yenCurrency)
      }
      let lineKinds = Set(ReceiptExtractor.currencyMarks(in: lineText, hasHangul: self.hasHangul).map {
        Self.resolved($0, yenCurrency: self.yenCurrency)
      })
      if lineKinds.count == 1, let kind = lineKinds.first {
        return kind
      }
      if self.receiptKinds.count == 1, let kind = self.receiptKinds.first {
        return kind
      }
      return self.receiptKinds.isEmpty && self.hasHangul ? .krw : nil
    }
  }
}
