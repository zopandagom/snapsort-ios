import Foundation

/// 언어 모델이 기프티콘 OCR 줄에서 찾은 답. 확인 전이다(`GifticonExtractor.filling`).
/// 모델이 적힌 그대로 복사하라는 지시를 따르지 않을 수 있어 원문과 대조하기 전에는 쓰지 않는다.
/// 사진에서 읽은 텍스트가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct GifticonModelAnswer: Sendable, Hashable {
  /// 만료일로 답한 텍스트(예: "2026.12.31 23:59").
  public let expiryText: String?
  /// 교환처로 답한 텍스트.
  public let redemptionPlace: String?

  public init(expiryText: String?, redemptionPlace: String?) {
    self.expiryText = expiryText
    self.redemptionPlace = redemptionPlace
  }
}

/// 규칙이 비운 필드를 언어 모델 답으로 채우는 확인 규칙 (docs/ARCHITECTURE.md §4 기프티콘 추출).
/// 모델은 원문에 없는 날짜·상호를 지어내고, 원문에 있는 다른 항목의 날짜(발행일·취소 기한)나 이미지 속 지시문의 날짜를
/// 만료일로 고를 수 있다. 그래서 만료일은 답이 원문에 그대로 있고, 그 날짜 앞이 만료 단서로 끝나며, 원문의 날짜 중 가장 늦을 때만
/// 받고, 값은 답의 표기가 아니라 원문 줄에서 규칙과 같은 방법(`rangeEnd`)으로 다시 계산한다. 교환처는 줄 전체나 줄 앞 단어일 때
/// 원문 표기로 받는다. 규칙이 단서를 보고 정한 필드(찾았거나 일부러 비움)는 모델을 쓰지 않는다.
/// 단서·다른 항목 단어 목록은 `ClassificationRules` 키워드 표와 따로 둔다(`scripts/mask-samples.py` 는 그 표만 읽는다).
extension GifticonExtractor {
  /// 모델 보강 버전. 기프티콘 확인 규칙(이 파일)이나 기프티콘 요청(기프티콘 instructions, `GifticonFields` 의 `@Guide`,
  /// 두 요청이 함께 쓰는 입력 형식 `ClassifierPrompt.text`·글자 수 상한·생성 옵션)을 바꿔 같은 줄에서 다른 기프티콘 값이 나올 수 있으면 올린다.
  /// 분류 요청(분류 instructions, `InformationKinds`)만 바꾸면 올리지 않는다(분류 보강은 보강 상태를 남기지 않는다).
  /// 저장소가 이 버전으로 보강하지 않은 행을 보강 대기로 돌려주고, 인덱서가 규칙 추출부터 다시 계산해 보강한다.
  public static let modelFillVersion = 1

  /// 모델 만료일 앞 텍스트가 이것으로 끝나야 하는 만료 단서. 공백 없이 소문자로 적는다.
  /// 맨 "기간" 은 넣지 않는다("이벤트 기간"). 임시 값이며 정확도 측정 작업에서 조정한다.
  static let modelExpiryClues = expiryLabels + [
    "기한", "만료", "유효", "사용가능기간", "교환기간", "교환가능기간", "validuntil", "validthru", "valid", "expires",
    "expiry", "expiration", "expirationdate", "exp", "expdate", "until",
  ]
  /// 만료 단서 앞에 있으면 만료일이 아닌 다른 항목(취소 기한·발행일·주문일 등)의 날짜로 보는 말. 공백 없이 소문자로 적는다.
  /// 임시 값이며 정확도 측정 작업에서 조정한다.
  static let otherItemWords = [
    "취소", "반품", "환불", "응모", "신청", "이벤트", "주문", "발행", "구매", "결제", "선물", "등록", "발급", "적립", "배송", "연장",
    "접수", "order", "issue", "purchase",
  ]
  /// 만료 단서로 보는 앞 텍스트의 최대 글자 수(공백 제외). 긴 문장(지시문) 속 날짜를 거른다. 임시 값이다.
  static let maximumClueLength = 20
  /// 모델 교환처의 최대 글자 수(공백 제외). 임시 값이다.
  static let maximumModelPlaceLength = 20
  /// 단서 텍스트 끝에서 빼는 구분 기호("유효기간:", "Valid until -", "만료(").
  private static let clueTrailingSymbols = Set(":：|)]）】([（【").union(rangeSeparators)

  /// 날짜 없이 기준일부터 센 상대 기간("구매일로부터 1년", "발급 후 90일"). 공백을 지운 텍스트에 대조한다.
  /// 숫자 뒤에 날짜가 이어지는 기간 시작("2026년 1월 1일부터 2026년 12월 31일")은 아니다.
  private static var relativePeriodPattern: Regex<Substring> { #/(?:로부터|부터|후)\d{1,3}(?:일|개월|달|년|주)/# }
  // `DateMention` 이 날짜로 읽지 않는 날짜 모양 조각(`hasUnreadDate`). Swift 정규식이 lookbehind 를 지원하지 않아
  // 앞 경계는 `hasUnreadDate` 가 앞 글자로 보고, 뒤 경계는 부정 전방탐색으로 쓴다.
  /// 연도 없는 월.일("12.31", "~ 3.31"). 뒤가 숫자나 기호로 이어지면 아니다.
  private static var unreadMonthDayPattern: Regex<Substring> { #/\d{1,2}[./\-]\d{1,2}(?![\d./\-])/# }
  /// 영문 월 이름 + 숫자("Dec 31, 2026", "dec.31"). 긴 이름부터 대조한다.
  private static var englishMonthDatePattern: Regex<Substring> {
    #/
      (?i)(?:january|february|march|april|may|june|july|august|september|sept|october|november|december
        |jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\.?\s*\d{1,2}
    /#
  }

  /// 연월만 있는 날짜("2026년 12월", "2026.12"). 월 뒤에 숫자가 이어지면("2026-1234") 아니다.
  private static var yearMonthPattern: Regex<Substring> { #/\d{4}\s*[./\-년]\s*\d{1,2}(?!\d)\s*월?/# }
  /// 일 없는 월("12월 말", "12월까지").
  private static var monthWithoutDayPattern: Regex<Substring> { #/\d{1,2}\s*월(?!\s*\d)/# }

  /// 규칙이 비운 필드 중 모델로 채울 수 있는 것이 있는지. 둘 다 찾았거나, 비운 필드가 규칙의 판단으로 막혀 있으면
  /// (만료일: 만료일 라벨 줄·"까지" 기한·상대 기간이 있음. 교환처: 교환처 라벨 줄이 있음) false 라 모델에 묻지 않는다.
  /// 줄이 없어도 false 다(대조할 원문이 없어 어떤 답도 확인을 통과할 수 없다).
  public static func needsModelFill(_ info: GifticonInfo, textLines: [RecognizedTextLine]) -> Bool {
    !textLines.isEmpty && ((info.expiryDate == nil && !self.hasRuleExpiryClue(textLines))
      || (info.redemptionPlace == nil && !self.hasRuleRedemptionPlaceLabel(textLines)))
  }

  /// `info` 의 nil 필드만, 원문으로 확인한 모델 답으로 채운다. 규칙이 찾은 필드는 그대로 둔다.
  /// 확인하지 못한 답은 버린다(그 필드는 nil 로 남는다). `referenceDate`·`calendar` 는 `extract` 와 같은 것을 넘긴다.
  /// 채운 필드는 `info.modelFilledFields` 에 더해 돌려준다(저장소가 필드별 출처로 저장하고 화면이 "추정"으로 보인다).
  /// 받는 값은 바뀌지 않으므로 출처를 담는 것만으로는 `modelFillVersion` 을 올리지 않는다.
  public static func filling(
    _ info: GifticonInfo,
    with answer: GifticonModelAnswer,
    from textLines: [RecognizedTextLine],
    referenceDate: Date?,
    calendar: Calendar
  ) -> GifticonInfo {
    let reference = referenceDate.map { LocalDate($0, calendar: calendar) }
    let modelExpiry = info.expiryDate == nil
      ? answer.expiryText.flatMap { self.modelExpiryDate(answer: $0, lines: textLines, reference: reference) }
      : nil
    let modelPlace = info.redemptionPlace == nil
      ? answer.redemptionPlace.flatMap { self.modelRedemptionPlace(answer: $0, lines: textLines) }
      : nil
    var filled = info.modelFilledFields
    if modelExpiry != nil {
      filled.insert(.expiryDate)
    }
    if modelPlace != nil {
      filled.insert(.redemptionPlace)
    }
    return GifticonInfo(
      expiryDate: info.expiryDate ?? modelExpiry,
      redemptionPlace: info.redemptionPlace ?? modelPlace,
      modelFilledFields: filled
    )
  }

  /// 출처 속성이 생기기 전에 지금 보강 버전으로 마친 행의 필드별 출처. `stored` 는 저장된 값, `rules` 는 같은 줄·생성일·달력으로
  /// 다시 계산한 규칙 값. 값이 있고 규칙 값과 다른 필드를 모델 출처로 본다(`filling` 은 규칙이 비운 필드만 채우므로 같은 버전에서
  /// 다른 값은 모델 값이다. 기준일·기기 달력이 바뀌어 규칙 값이 달라진 경우도 모델로 보아 "추정"으로 보인다 — 확인된 값처럼 보이지 않는 쪽).
  /// 값은 바꾸지 않는다.
  public static func modelFilledFields(stored: GifticonInfo, rules: GifticonInfo) -> Set<GifticonInfo.Field> {
    var fields: Set<GifticonInfo.Field> = []
    if stored.expiryDate != nil, stored.expiryDate != rules.expiryDate {
      fields.insert(.expiryDate)
    }
    if stored.redemptionPlace != nil, stored.redemptionPlace != rules.redemptionPlace {
      fields.insert(.redemptionPlace)
    }
    return fields
  }

  // MARK: - 만료일

  /// 규칙이 만료일 단서를 봤는지: 만료일 라벨 줄, "까지" 붙은 날짜, 상대 기간 중 하나라도 있다.
  /// 규칙은 이 단서로 만료일을 찾거나 모호해서 일부러 비운다. 모델이 그 판단을 덮지 않게 한다.
  static func hasRuleExpiryClue(_ lines: [RecognizedTextLine]) -> Bool {
    let relativePeriod = self.relativePeriodPattern
    return !self.labeledLines(lines, labels: self.expiryLabels).isEmpty
      || lines.contains { line in
        DateMention.mentions(in: line.text).contains { self.hasExpirySuffix(after: $0.match, in: line.text) }
          || self.compact(line.text).contains(relativePeriod)
      }
  }

  /// 모델이 만료일로 답한 텍스트를 원문으로 확인한 만료일. 확인하지 못하면 nil.
  /// - 답에 날짜가 있고 원문 줄에 (공백·대소문자를 무시하고) 그대로 있다. 답을 포함한 자리가 여럿이면 모두 확인되고 같은 날짜여야 한다.
  /// - 자리마다 답과 겹치는 첫 날짜에서 기간 시작까지 거슬러 간 앞 텍스트가 만료 단서다(`isExpiryClue`).
  /// - 값은 기간 시작부터 `rangeEnd` 로 다시 계산한 날짜이고, 답이 그 끝 날짜를 포함한다(기간 시작만 답하면 받지 않는다).
  /// - 원문의 모든 날짜가 연도까지 정해지고 이 날짜보다 늦지 않다(`isLatestDate`).
  static func modelExpiryDate(answer: String, lines: [RecognizedTextLine], reference: LocalDate?) -> LocalDate? {
    guard !DateMention.mentions(in: answer).isEmpty, !self.hasRuleExpiryClue(lines) else { return nil }
    let needle = self.foldedCharacters(answer).map(\.character)
    var expiry: LocalDate?
    for line in lines {
      for occurrence in self.occurrences(of: needle, in: line.text) {
        guard let date = self.confirmedExpiry(
          answer: needle,
          at: occurrence,
          on: line,
          in: lines,
          reference: reference
        ),
          expiry.map({ $0 == date }) ?? true
        else { return nil }
        expiry = date
      }
    }
    guard let expiry, self.isLatestDate(expiry, in: lines, reference: reference) else { return nil }
    return expiry
  }

  /// 줄의 `occurrence` 자리에 있는 답이 가리키는 만료일. 앞 텍스트가 만료 단서가 아니거나 기간의 끝을 정하지 못하면 nil.
  private static func confirmedExpiry(
    answer: [String],
    at occurrence: Range<String.Index>,
    on line: RecognizedTextLine,
    in lines: [RecognizedTextLine],
    reference: LocalDate?
  ) -> LocalDate? {
    let text = line.text
    let mentions = DateMention.mentions(in: text)
    guard var start = mentions.firstIndex(where: { $0.match.range.overlaps(occurrence) }) else { return nil }
    while start > 0, self.isRange(from: mentions[start - 1].match, to: mentions[start].match, in: text) {
      start -= 1
    }
    let startBound = mentions[start].match.range.lowerBound
    guard self.isExpiryClue(before: text[..<startBound], on: line, in: lines) else { return nil }
    let rest = String(text[startBound...])
    // 끝을 읽지 못한 기간·다음 줄로 넘어간 기간·달력에 없는 날짜는 `.date` 가 아니다.
    guard case let .date(date, isEndFixed) = self.rangeEnd(in: rest, reference: reference, notBefore: nil),
          self.contains(answer, endOf: date, in: rest, reference: reference)
    else { return nil }
    // 줄 끝 날짜의 오른쪽이나 아래 줄이 이어짐 표시(이어짐 기호·영문 잇는 말)와 날짜 모양으로 시작하면(끝을 읽든 못 읽든,
    // "2026.10.01" / "~ 2027.03.31") 그 날짜는 기간 시작이다.
    if !isEndFixed {
      let neighbors = self.neighborLines(of: line, in: lines)
      if [neighbors.sameRow, neighbors.below]
        .contains(where: { $0.flatMap { self.leadingContinuation($0.text, base: date) } != nil })
      {
        return nil
      }
    }
    return date
  }

  /// 답이 `text`(기간 시작부터의 줄) 안의 날짜 중 `date` 로 풀리는 첫 날짜의 표기를 포함하는지.
  private static func contains(
    _ answer: [String],
    endOf date: LocalDate,
    in text: String,
    reference: LocalDate?
  ) -> Bool {
    let mentions = DateMention.mentions(in: text)
    guard let end = mentions.indices.first(where: {
      self.resolvedDate(at: $0, of: mentions, in: text, base: reference) == date
    })
    else { return false }
    let endText = self.foldedCharacters(String(text[mentions[end].match.range])).map(\.character)
    return !self.occurrences(of: endText, in: answer.joined()).isEmpty
  }

  /// 날짜 앞 텍스트가 만료 단서인지. 비었으면(날짜만 있는 줄) 그 줄을 오른쪽 같은 높이나 바로 아래 줄로 갖는 줄(단서 후보 줄)이
  /// 하나 이상 있고 그 전부의 텍스트가 만료 단서여야 한다. 하나라도 아니면(위 "Valid", 왼쪽 "발행일") 어느 항목의 날짜인지 모른다.
  private static func isExpiryClue(
    before prefix: Substring,
    on line: RecognizedTextLine,
    in lines: [RecognizedTextLine]
  ) -> Bool {
    let clue = self.clueText(prefix)
    guard clue.isEmpty else { return self.isExpiryClueText(clue) }
    let candidates = lines.filter { other in
      guard other != line else { return false }
      let neighbors = self.neighborLines(of: other, in: lines)
      return neighbors.sameRow == line || neighbors.below == line
    }
    return !candidates.isEmpty && candidates.allSatisfy { self.isExpiryClueText(self.clueText($0.text)) }
  }

  /// 만료 단서로 끝나고, 다른 항목 단어가 없고, 기준 길이 이하인지.
  private static func isExpiryClueText(_ clue: String) -> Bool {
    clue.count <= self.maximumClueLength
      && self.modelExpiryClues.contains { clue.hasSuffix($0) }
      && !self.otherItemWords.contains { clue.contains($0) }
  }

  /// 공백을 지우고 소문자로 바꾼 뒤 앞쪽 기호("[", "■")와 끝 구분 기호를 뺀 텍스트.
  private static func clueText(_ text: some StringProtocol) -> String {
    var clue = Substring(self.compact(text).lowercased()).drop { !$0.isLetter && !$0.isNumber }
    while let last = clue.last, self.clueTrailingSymbols.contains(last) {
      clue.removeLast()
    }
    return String(clue)
  }

  /// 원문의 모든 날짜가 연도까지 정해지고 `date` 보다 늦지 않은지. `DateMention` 이 읽지 못하는 날짜 모양(`hasUnreadDate`)이 있거나
  /// 연도를 생략했는데 기준일이 없거나 달력에 없는 날짜가 있으면, 더 늦은 만료일이 있을 수 있어 false 다.
  private static func isLatestDate(_ date: LocalDate, in lines: [RecognizedTextLine], reference: LocalDate?) -> Bool {
    lines.allSatisfy { line in
      let mentions = DateMention.mentions(in: line.text)
      let isResolved = mentions.indices.allSatisfy { index in
        self.resolvedDate(at: index, of: mentions, in: line.text, base: reference).map { $0 <= date } ?? false
      }
      return isResolved && !self.hasUnreadDate(line.text, mentions: mentions)
    }
  }

  /// `mentions` 와 겹치지 않는 날짜 모양 조각이 있는지: 달력에 있을 수 있는 연도 없는 월.일, 영문 월 이름 + 숫자, 연월만, 일 없는 월.
  /// 월.일·연월은 앞 글자가 숫자나 기호(".", "/", "-")면 더 긴 숫자열(쿠폰 번호·전화번호)이나 날짜의 일부라 세지 않는다.
  /// 영문 월은 앞 글자가 영문자면 다른 단어의 일부("decaf 3")라 세지 않는다(한글 뒤 "유효Dec 31" 은 센다).
  private static func hasUnreadDate(_ text: String, mentions: [DateMention]) -> Bool {
    func isUnread(_ range: Range<String.Index>, unlessAfter isJoined: (Character) -> Bool) -> Bool {
      let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
      return !(before.map(isJoined) ?? false) && !mentions.contains { $0.match.range.overlaps(range) }
    }
    let isNumberOrJoiner: (Character) -> Bool = { $0.isNumber || "./-".contains($0) }
    let monthDay = text.matches(of: self.unreadMonthDayPattern).contains { match in
      let numbers = match.output.split { !$0.isNumber }.compactMap { Int($0) }
      return numbers.count == 2 && (1 ... 12).contains(numbers[0]) && (1 ... 31).contains(numbers[1])
        && isUnread(match.range, unlessAfter: isNumberOrJoiner)
    }
    let englishMonth = text.matches(of: self.englishMonthDatePattern)
      .contains { isUnread($0.range, unlessAfter: { $0.isASCII && $0.isLetter }) }
    let yearMonth = text.matches(of: self.yearMonthPattern)
      .contains { isUnread($0.range, unlessAfter: isNumberOrJoiner) }
    let monthOnly = text.matches(of: self.monthWithoutDayPattern)
      .contains { isUnread($0.range, unlessAfter: \.isNumber) }
    return monthDay || englishMonth || yearMonth || monthOnly
  }

  // MARK: - 교환처

  /// 교환처 라벨 줄(안내문 제외, `redemptionPlaceLabelLines`)이 있는지. 있으면 규칙의 판단(라벨 값, 로고라 읽은 값이 없음,
  /// 값이 다른 항목)을 따른다.
  static func hasRuleRedemptionPlaceLabel(_ lines: [RecognizedTextLine]) -> Bool {
    !self.redemptionPlaceLabelLines(lines).isEmpty
  }

  /// 모델이 교환처로 답한 텍스트를 원문으로 확인한 교환처. 날짜가 없는 줄(만료일 라벨 줄 아님)의 전체이거나 줄 앞 단어일 때
  /// 그 줄의 원문 표기를 돌려준다. 문장 속 상호("…애플스토어에서 사용"), 원문에 없는 상호, 날짜나 긴 숫자(쿠폰 번호)가 든 답은 nil.
  static func modelRedemptionPlace(answer: String, lines: [RecognizedTextLine]) -> String? {
    guard !self.hasRuleRedemptionPlaceLabel(lines), let value = self.cleanedValue(answer),
          value.contains(where: \.isLetter), self.compact(value).count <= self.maximumModelPlaceLength,
          DateMention.mentions(in: value).isEmpty, !self.compact(value).contains(#/\d{4}/#)
    else { return nil }
    let needle = self.foldedCharacters(value).map(\.character)
    let expiryLabelLines = Set(self.labeledLines(lines, labels: self.expiryLabels).map(\.line))
    return lines.lazy
      .filter { !expiryLabelLines.contains($0) && DateMention.mentions(in: $0.text).isEmpty }
      .compactMap { self.leadingText(matching: needle, in: $0.text) }
      .first
      .map(String.init)
  }

  /// 줄 앞 기호를 건너뛴 텍스트가 `needle`(공백 없이 소문자) 로 시작하고 바로 뒤가 공백이나 줄 끝이면 그 원문 범위.
  /// 줄 안의 공백은 무시한다("스타 벅스").
  private static func leadingText(matching needle: [String], in text: String) -> Substring? {
    guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return nil }
    var index = start
    for expected in needle {
      while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
      }
      guard index < text.endIndex, text[index].lowercased() == expected else { return nil }
      index = text.index(after: index)
    }
    guard index == text.endIndex || text[index].isWhitespace else { return nil }
    return text[start ..< index]
  }

  // MARK: - 대조

  /// 공백을 뺀 글자마다 소문자로 바꾼 것과 원문 위치.
  private static func foldedCharacters(_ text: String) -> [(character: String, index: String.Index)] {
    text.indices.filter { !text[$0].isWhitespace }.map { (text[$0].lowercased(), $0) }
  }

  /// `needle`(공백 없이 소문자로 바꾼 글자)이 `text` 에 공백·대소문자를 무시하고 나오는 원문 범위들.
  private static func occurrences(of needle: [String], in text: String) -> [Range<String.Index>] {
    let characters = self.foldedCharacters(text)
    guard !needle.isEmpty, needle.count <= characters.count else { return [] }
    return (0 ... characters.count - needle.count)
      .filter { start in characters[start ..< start + needle.count].map(\.character).elementsEqual(needle) }
      .map { start in characters[start].index ..< text.index(after: characters[start + needle.count - 1].index) }
  }
}
