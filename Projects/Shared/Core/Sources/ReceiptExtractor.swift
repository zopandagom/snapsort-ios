import CoreGraphics
import Foundation

/// 영수증 이미지의 OCR 줄에서 가게·금액·통화·취소를 찾는 규칙 (docs/ARCHITECTURE.md §4 영수증 추출).
/// 원칙은 "틀린 값보다 빈 값"이다: 고를 근거가 둘 이상으로 갈리거나 줄의 뜻이 불분명하면 금액 모름·가게 모름으로 둔다.
/// 표의 낱말은 네 방식(줄 라벨·낱말 같음·줄 같음·줄 머리 낱말) 중 하나로 대조하고, 띄어 쓰지 않는 표기(한글·한자·가나)는
/// 표마다 정한 곳(값 범위의 끊는 말, 3자 이상 상태 라벨·머리말)에서만 부분 문자열·붙은 값으로 맞춘다. 표는 +Tables.swift.
/// 금액(라벨 줄 → 이웃 줄 → 단계별 고르기) → 취소 → 가게 순서로 찾는다. 언어 모델 보강은 없다.
/// 라벨은 `ClassificationRules` 키워드 표·기프티콘 라벨 표와 따로 둔다(`scripts/mask-samples.py` 는 키워드 표만 읽는다).
/// 결과에 사진에서 읽은 텍스트(가게·금액)가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public enum ReceiptExtractor {
  /// 추출 규칙 버전. 규칙을 바꿔 같은 줄에서 다른 값이 나올 수 있으면 올린다.
  /// 저장소가 이 버전으로 추출하지 않은 행을 다시 추출 대상으로 돌려준다.
  public static let rulesVersion = 1

  /// 영수증으로 분류한 이미지의 OCR 줄에서 가게·금액·통화·취소를 찾는다. 날짜를 쓰지 않아 달력·기준일을 받지 않는다.
  public static func extract(from textLines: [RecognizedTextLine]) -> ReceiptInfo {
    let lines = textLines.map(Line.init)
    let context = CurrencyContext(texts: lines.map(\.text))
    let labeled = lines.indices.compactMap { self.labeledAmount(at: $0, in: lines, context: context) }
    let chosen = self.chosenAmount(from: labeled)
    let isCancelled = chosen.isNegative
      || labeled.contains { $0.stage == 3 && $0.value?.token.isPositive == true }
      || self.hasCancelTitleOrStatus(in: lines, context: context)
    return ReceiptInfo(
      storeName: self.storeName(in: lines, context: context),
      amount: chosen.amount,
      isCancelled: isCancelled
    )
  }

  /// 가게별 묶음 키: 소문자, 공백 제거, 법인 표기 제거, 글자·숫자만 남긴다. 지점 이름은 남긴다. 글자·숫자가 남지 않으면 nil.
  /// 공백을 먼저 지워 "Co., Ltd." 처럼 띄어 쓴 법인 표기도 지우고, 법인 표기는 맨 앞·맨 끝에서만 지운다("Zinc.Cafe" 는 그대로).
  public static func storeKey(_ storeName: String) -> String? {
    var name = Substring(storeName.lowercased().filter { !$0.isWhitespace })
    while let mark = self.corporateMarks.first(where: { name.hasPrefix($0) || name.hasSuffix($0) }) {
      name = name.hasPrefix(mark) ? name.dropFirst(mark.count) : name.dropLast(mark.count)
    }
    let key = String(name.filter { $0.isLetter || $0.isNumber })
    return key.isEmpty ? nil : key
  }

  /// 묶음 키에서 지우는 법인 표기. 소문자·공백 없이 적고 긴 것부터 지운다("co.,ltd." 를 "ltd." 보다 먼저).
  static let corporateMarks = [
    "co.,ltd.", "co.,ltd", "주식회사", "유한회사", "株式会社", "(주)", "(유)", "(株)", "ltd.", "inc.", "corp.", "㈜", "㈱",
  ]

  /// 검사에 쓰는 줄. 원문은 그대로 두고 연속 점·말줄임·가운뎃점(점 리더 "TOTAL.......45.20")을 공백 하나로 바꾼 사본을 쓴다.
  struct Line {
    let text: String
    let original: String
    let box: CGRect

    init(_ line: RecognizedTextLine) {
      self.original = line.text
      self.text = line.text.replacing(#/[.…·]{2,}/#, with: " ")
      self.box = line.boundingBox
    }
  }
}

// 표·대조 방식·금액·취소. 진입점과 줄은 위 본문에 둔다.
extension ReceiptExtractor {
  // MARK: - 대조 방식

  /// 줄 라벨 바로 뒤 경계로 받는 글자(공백·숫자 밖).
  private static let labelBoundaries: Set<Character> = [
    ":", "：", "]", ")", "|", "-", "(", "（", "[", "【", "】", "）", "−", "+", "₩", "￦", "$", "€", "¥", "￥",
  ]

  /// 줄 라벨: 줄 맨 앞(앞쪽 기호는 건너뛴다)의 라벨과 그 뒤 원래 텍스트. 긴 라벨부터 대조하고, 라벨 바로 뒤가 경계여야 한다
  /// (`acceptsAttached` 면 경계 없이 붙은 값도 받는다). "Totally"·"상호저축은행" 은 라벨이 아니다.
  static func lineLabel(
    _ labels: [String],
    in text: String,
    acceptsAttached: Bool = false
  ) -> (label: String, rest: Substring)? {
    for label in labels.sorted(by: { $0.count > $1.count }) {
      guard let rest = self.receiptText(after: label, in: text) else { continue }
      if acceptsAttached || rest.first
        .map({ $0.isWhitespace || $0.isNumber || self.labelBoundaries.contains($0) }) ?? true
      {
        return (label, rest)
      }
    }
    return nil
  }

  /// 영수증 전용 줄 라벨 대조: 줄 맨 앞(앞쪽 기호는 건너뛴다)에 `label` 이 있으면 그 뒤의 원래 텍스트. 라벨 안의 공백과 마침표는
  /// 건너뛰어("Orig. Trans" = origtrans) 맞춘다. 라벨 바로 뒤에 조사가 붙고 띄어 쓰면 안내문이라 라벨이 아니다
  /// (기프티콘 `GifticonExtractor.text(after:in:)` 와 같은 규칙에 마침표 건너뛰기만 더했다).
  static func receiptText(after label: String, in text: String) -> Substring? {
    guard var index = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return nil }
    for expected in label {
      while index < text.endIndex, text[index].isWhitespace || text[index] == "." && expected != "." {
        index = text.index(after: index)
      }
      guard index < text.endIndex, text[index].lowercased() == String(expected) else { return nil }
      index = text.index(after: index)
    }
    if index < text.endIndex, GifticonExtractor.labelParticles.contains(text[index]),
       text[text.index(after: index)...].first?.isWhitespace ?? true
    {
      return nil
    }
    return text[index...]
  }

  /// 낱말 같음에 쓰는 낱말: 소문자, 앞뒤 기호(`[]()<>【】（）*#`)와 끝 문장 부호(`.`·`:`·`,`)를 빼고 Unicode NFC 로 맞춘다
  /// (OCR 이 "é" 를 분해형으로 줘도 표의 말과 같다).
  static func normalizedWord(_ word: some StringProtocol) -> String {
    let symbols = CharacterSet(charactersIn: "[]()<>【】（）*#")
    return word.lowercased().trimmingCharacters(in: symbols)
      .trimmingCharacters(in: CharacterSet(charactersIn: ".:,"))
      .trimmingCharacters(in: symbols)
      .precomposedStringWithCanonicalMapping
  }

  static func words(_ text: some StringProtocol) -> [Substring] {
    text.split(whereSeparator: \.isWhitespace).map { Substring($0) }
  }

  /// 줄 같음에 쓰는 키: 공백 없이 소문자로, 기호(`[]()<>【】（）*#=-`)와 아포스트로피는 어디 있든 빼고 끝 문장 부호를 뺀 뒤 NFC 로
  /// 맞춘다("TICKET D'ANNULATION" = ticketdannulation).
  static func lineKey(_ text: some StringProtocol) -> String {
    let removed = Set("[]()<>【】（）*#=-'’")
    return String(text.lowercased().filter { !$0.isWhitespace && !removed.contains($0) })
      .trimmingCharacters(in: CharacterSet(charactersIn: ".:,!"))
      .precomposedStringWithCanonicalMapping
  }

  /// 줄 같음: 키가 `words`·`fragments` 의 낱말을 이어 붙인 것과 같고, `words` 의 낱말이 하나 이상 들었거나 조각 낱말이 둘 이상이다.
  static func isLine(_ key: String, joinedFrom words: Set<String>, fragments: Set<String> = []) -> Bool {
    let characters = Array(key)
    guard !characters.isEmpty else { return false }
    // 위치마다 그 위치까지 이어 붙일 수 있는 (낱말이 들었는지, 조각 수(2 이상은 2)) 상태.
    var states: [Set<Int>] = Array(repeating: [], count: characters.count + 1)
    states[0] = [0]
    for start in characters.indices where !states[start].isEmpty {
      for end in start + 1 ... characters.count {
        let piece = String(characters[start ..< end])
        let isWord = words.contains(piece)
        guard isWord || fragments.contains(piece) else { continue }
        for state in states[start] {
          let hasWord = state >= 3 || isWord
          let fragmentCount = min(2, state % 3 + (isWord ? 0 : 1))
          states[end].insert((hasWord ? 3 : 0) + fragmentCount)
        }
      }
    }
    return states[characters.count].contains { $0 >= 3 || $0 == 2 }
  }

  // MARK: - 금액

  /// 값을 찾은 금액 라벨 줄(또는 이웃 줄 값).
  struct LabeledAmount {
    let stage: Int
    /// 그 줄의 값과 통화. nil 이면 값이 갈렸다(할인 뒤 금액·첫 묶음의 다른 금액). 그 단계의 갈린 후보로 센다.
    let value: (token: AmountToken, currency: ReceiptCurrency?)?
  }

  /// 줄 맨 앞이 금액 라벨이고 라벨 줄 판정을 통과하면 그 값. 범위에 토큰이 없으면 이웃 줄을 본다.
  private static func labeledAmount(at index: Int, in lines: [Line], context: CurrencyContext) -> LabeledAmount? {
    let line = lines[index]
    guard let (label, rest) = self.lineLabel(self.allAmountLabels, in: line.text),
          let stage = self.amountLabels.first(where: { $0.value.contains(label) })?.key,
          self.isAmountLabelLine(rest, context: context)
    else { return nil }
    switch self.lineValue(rest, context: context) {
    case let .token(token):
      // 환불 금액 뒤에 대기·부정 말이나("Refund amount 12.00 pending") 환불을 되돌린 취소 말이 있으면("환불금액 9,000 취소")
      // 취소 근거도 금액 후보도 아니다.
      if stage == 3, self.hasPendingTail(rest, context: context)
        || self.refundAmountLabels.contains(label) && self.hasCancelTail(rest, context: context)
      {
        return nil
      }
      return LabeledAmount(stage: stage, value: (token, context.currency(of: token, lineText: String(rest))))
    case .split:
      return LabeledAmount(stage: stage, value: nil)
    case .empty(hasLetters: true):
      return nil
    case .empty(hasLetters: false):
      guard let (neighbor, token) = self.neighborAmount(of: index, in: lines, context: context) else { return nil }
      let lineText = String(rest) + " " + lines[neighbor].text
      return LabeledAmount(stage: stage, value: (token, context.currency(of: token, lineText: lineText)))
    }
  }

  /// 범위에 토큰이 없을 때 이웃 줄의 금액: 같은 높이 오른쪽 줄 중 줄 전체가 금액 토큰 하나인 가장 오른쪽 줄(그보다 오른쪽에 다른
  /// 줄이 있으면 열을 믿을 수 없어 없음), 같은 높이 후보가 없을 때만 바로 아래 줄(그 줄과 같은 높이에 다른 금액 줄이 없을 때만).
  private static func neighborAmount(
    of index: Int,
    in lines: [Line],
    context: CurrencyContext
  ) -> (Int, AmountToken)? {
    let box = lines[index].box
    let others = lines.indices.filter { $0 != index && !self.startsWithReceiptLabel(lines[$0].text) }
    let single = { (other: Int) in self.singleToken(in: lines[other].text, hasHangul: context.hasHangul) }
    let sameRow = others.filter {
      abs(lines[$0].box.midY - box.midY) < box.height / 2 && lines[$0].box.minX >= box.midX
    }
    if !sameRow.isEmpty {
      guard let best = sameRow.filter({ single($0) != nil }).max(by: { lines[$0].box.maxX < lines[$1].box.maxX }),
            let token = single(best),
            !sameRow.contains(where: { single($0) == nil && lines[$0].box.maxX > lines[best].box.maxX })
      else { return nil }
      return (best, token)
    }
    guard let below = others.filter({
      let other = lines[$0].box
      return other.minY >= box.midY && other.minY - box.maxY <= box.height * GifticonExtractor.maximumLineGapRatio
        && other.maxX > box.minX && other.minX < box.maxX
    }).min(by: { lines[$0].box.minY < lines[$1].box.minY }),
      let token = single(below)
    else { return nil }
    let belowBox = lines[below].box
    let hasOtherColumn = others.contains {
      $0 != below && abs(lines[$0].box.midY - belowBox.midY) < belowBox.height / 2 && single($0) != nil
    }
    return hasOtherColumn ? nil : (below, token)
  }

  /// 줄 전체가 금액 토큰 하나(앞뒤 공백·통화 표시 낱말만)면 그 토큰.
  static func singleToken(in text: String, hasHangul: Bool) -> AmountToken? {
    var characters = self.masked(text)
    let tokens = self.amountTokens(in: characters, hasHangul: hasHangul)
    guard tokens.count == 1, let token = tokens.first else { return nil }
    characters.replaceSubrange(token.range, with: [" "])
    let rest = self.words(String(characters))
    return rest.allSatisfy { self.currencyWords.contains(self.normalizedWord($0)) } ? token : nil
  }

  /// 영수증 라벨(금액·가게·취소)로 시작하는 줄. 이웃 줄 값으로 고르지 않는다.
  static func startsWithReceiptLabel(_ text: String) -> Bool {
    self.lineLabel(
      self.allAmountLabels + self.storeLabels + self.shortStoreLabels + self.cancelStatusLabels + self
        .cancelHeaderLabels + self.latinCancelHeaderLabels,
      in: text
    ) != nil
  }

  /// 고른 금액과 취소 근거(같은 값 후보 중 음수가 있음).
  struct ChosenAmount {
    var amount: ReceiptAmount?
    var isNegative = false
  }

  /// 라벨 줄 중 가장 높은 단계(1·2, 없으면 3)의 값. 그 단계의 값(수·통화)이 모두 같으면 그 값, 다르거나 값이 갈린 줄이 있으면
  /// 금액 모름. 같은 값 후보 중 그 통화로 최소 단위를 만들 수 있는 토큰을 쓰고("합계 9.000"·"합계 9,000원" 은 ₩9,000),
  /// 음수 후보가 하나라도 있으면 취소 근거다.
  private static func chosenAmount(from labeled: [LabeledAmount]) -> ChosenAmount {
    guard let stage = labeled.filter({ $0.stage < 3 }).map(\.stage).min() ?? labeled.map(\.stage).min() else {
      return ChosenAmount()
    }
    let candidates = labeled.filter { $0.stage == stage }
    let values = candidates.compactMap(\.value)
    let distinct = Set(values.map { "\($0.token.numberKey)|\($0.currency?.rawValue ?? "?")" })
    guard values.count == candidates.count, distinct.count == 1, let first = values.first else {
      return ChosenAmount()
    }
    var chosen = ChosenAmount(isNegative: values.contains { $0.token.isNegative })
    guard let currency = first.currency else { return chosen }
    let usable = values.filter { $0.token.amount(in: currency) != nil }
    chosen.amount = (usable.first { $0.token.isNegative } ?? usable.first)?.token.amount(in: currency)
    return chosen
  }

  // MARK: - 취소

  /// 취소 전표 이름 줄(위치 무관), 첫 금액 줄보다 위의 상태 문구 줄, 취소 상태 줄·취소 머리말 줄이 있는지.
  private static func hasCancelTitleOrStatus(in lines: [Line], context: CurrencyContext) -> Bool {
    let ordered = lines.sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }
    let firstAmount = ordered.firstIndex {
      !self.amountTokens(in: self.masked($0.text), hasHangul: context.hasHangul).isEmpty
    } ?? ordered.count
    for (position, line) in ordered.enumerated() {
      let key = self.lineKey(line.text)
      if self.isLine(key, joinedFrom: self.cancelTitles)
        || position < firstAmount && self.isLine(key, joinedFrom: self.cancelStatusPhrases)
        || self.lineLabel(self.cancelHeaderLabels, in: line.text, acceptsAttached: true) != nil
        || self.lineLabel(self.latinCancelHeaderLabels, in: line.text).map({ self.isNumberValue($0.rest) }) == true
      {
        return true
      }
      // 3자 이상 한글·한자·가나 상태 라벨은 붙은 값도 받고("거래구분신용취소"), 2자·라틴 라벨은 뒤 경계가 필요하다("상태불량시").
      if let (_, rest) = self.lineLabel(self.attachedCancelStatusLabels, in: line.text, acceptsAttached: true)
        ?? self.lineLabel(self.boundedCancelStatusLabels, in: line.text),
        let value = self.cleanedValue(rest), self.isCancelStatusValue(value)
      {
        return true
      }
    }
    return false
  }

  /// 라틴 취소 머리말 뒤 값이 번호·날짜인지: 구분 기호(`:`·`#`)와 번호 표시 낱말 하나(No.·Nr.·Date 등)를 건너뛴 첫 낱말이 숫자로
  /// 시작한다("Original Receipt No. 1234", "Orig Trans Date: 10/01/2026"). 안내문("… REQUIRED FOR RETURNS")은 아니다.
  private static func isNumberValue(_ rest: Substring) -> Bool {
    var words = self.words(rest).filter { !$0.allSatisfy { ":：#".contains($0) } }[...]
    if let first = words.first, self.numberMarkerWords.contains(self.normalizedWord(first)) {
      words = words.dropFirst()
    }
    return words.first?.drop { ":：#".contains($0) }.first?.isNumber == true
  }
}
