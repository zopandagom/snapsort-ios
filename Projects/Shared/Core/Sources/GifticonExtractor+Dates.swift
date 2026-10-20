import Foundation

extension GifticonExtractor {
  /// `mentions[index]` 의 날짜. 연도를 생략했으면 기간으로 이어진 앞 날짜 중 연도가 적힌 가장 가까운 날짜 이후,
  /// 없으면 `base` 이후 처음 오는 그 날짜다("2026년 1월 1일 ~ 12월 31일" 의 끝을 기준일 연도로 보내지 않는다).
  /// 연도가 적힌 앞 날짜가 달력에 없으면("2026.02.30 ~ 12월 31일") 연도를 알 수 없어 nil 이다.
  static func resolvedDate(
    at index: Int,
    of mentions: [DateMention],
    in text: String,
    base: LocalDate?
  ) -> LocalDate? {
    guard let anchor = self.yearAnchor(at: index, of: mentions, in: text) else {
      return mentions[index].resolved(onOrAfter: base)
    }
    return anchor.resolved(onOrAfter: nil).flatMap { mentions[index].resolved(onOrAfter: $0) }
  }

  /// `mentions[index]` 로 끝나는 기간(기간으로 이어진 앞 날짜들) 앞에 글자가 있는지.
  static func hasTextBeforeRange(ending index: Int, of mentions: [DateMention], in text: String) -> Bool {
    var start = index
    while start > 0, self.isRange(from: mentions[start - 1].match, to: mentions[start].match, in: text) {
      start -= 1
    }
    return self.compact(text[..<mentions[start].match.range.lowerBound]).contains(where: \.isLetter)
  }

  /// 연도가 적힌 날짜면 자기 자신, 아니면 기간으로 이어진 앞 날짜 중 연도가 적힌 가장 가까운 날짜. 없으면 nil.
  static func yearAnchor(at index: Int, of mentions: [DateMention], in text: String) -> DateMention? {
    var start = index
    while start > 0, self.isRange(from: mentions[start - 1].match, to: mentions[start].match, in: text) {
      start -= 1
    }
    return mentions[start ... index].last { $0.year != nil }
  }

  /// 영문 월 이름. 긴 것부터 대조한다("december" 를 "dec" 로 자르지 않는다).
  static let englishMonthNames = [
    "january", "february", "march", "april", "may", "june", "july", "august", "september", "sept", "october",
    "november", "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
  ].sorted { $0.count > $1.count }

  /// 두 날짜 사이 글 전체가 이것이면 기간을 잇는 말로 본다("2026.01.01 to 2026.12.31", "2026.01.01에서 2026.12.31").
  /// 공백 없이 소문자로 적는다. 영문만 줄 맨 앞의 이어짐 표시로도 쓴다(`leadingRangeMarker`).
  static let rangeJoinWords = ["to", "until", "through", "thru", "till", "에서", "내지"]
  /// 줄 맨 앞에서 이어짐 표시로 보는 영문 잇는 말.
  private static let englishRangeJoinWords = rangeJoinWords.filter { $0.allSatisfy(\.isASCII) }
    .sorted { $0.count > $1.count }
  /// 기간에만 쓰이는 이어짐 기호. 줄표("-", "–", "—")는 글머리표로도 쓰인다.
  private static let tildeSeparators: Set<Character> = ["~", "～", "∼", "〜"]

  /// 공백을 지운 텍스트가 날짜 모양으로 시작하는지: 숫자로 시작하거나("12.31", "2027년 10월"), 영문 날짜 앞부분
  /// (`englishDatePrefix`)으로 시작한다. 이어짐 기호·잇는 말 뒤에서 끝 날짜를 읽지 못한 기간인지 볼 때 쓴다.
  /// 안내문("사용시확인", "maybe", "march-madness")은 아니다.
  static func startsWithUnreadDate(_ compact: Substring) -> Bool {
    compact.first?.isNumber == true || self.englishDatePrefix(compact)
  }

  /// 공백을 지운 텍스트가 영문 날짜 앞부분으로 시작하는지(대소문자 무시): 월 이름 + (점 하나) + 숫자("dec31", "dec.31", "dec2026"),
  /// 1~2자리 숫자 + (서수 st·nd·rd·th) + 월 이름("31dec", "31stdecember"), 4자리 숫자 + 월 이름("2026dec").
  static func englishDatePrefix(_ compact: Substring) -> Bool {
    if self.englishMonthPrefix(of: compact) != nil {
      return true
    }
    let lowercased = compact.lowercased()
    let digits = lowercased.prefix { $0.isASCII && $0.isNumber }
    var rest = lowercased.dropFirst(digits.count)
    switch digits.count {
    case 1 ... 2:
      if let ordinal = ["st", "nd", "rd", "th"].first(where: { rest.hasPrefix($0) }) {
        rest = rest.dropFirst(ordinal.count)
      }
    case 4:
      break
    default:
      return false
    }
    return self.englishMonthNames.contains { rest.hasPrefix($0) }
  }

  /// 공백을 지운 텍스트가 영문 월 이름 + (점 하나) + 숫자로 시작하면 그 월 이름(대소문자 무시).
  static func englishMonthPrefix(of compact: Substring) -> String? {
    let lowercased = compact.lowercased()
    guard let month = self.englishMonthNames.first(where: { lowercased.hasPrefix($0) }) else { return nil }
    var rest = lowercased.dropFirst(month.count)
    if rest.first == "." {
      rest = rest.dropFirst()
    }
    return rest.first?.isNumber == true ? month : nil
  }

  /// 줄 맨 앞(앞 공백 제외)의 이어짐 표시 뒤 텍스트와, 표시가 기간 표시인지. 표시는 이어짐 기호 하나, 또는 영문 잇는 말 뒤에
  /// 공백이나 공백 없는 날짜 모양이 오는 것이다("to 2026.12.31", "to2026.12.31". "today"·"total 3" 은 아니다.
  /// "to 3명" 은 표시지만 뒤가 날짜 모양이 아니라 `leadingContinuation` 이 거른다).
  /// 기간 표시(물결표 계열·영문 잇는 말)는 기간에만 쓰이고, 줄표는 글머리표로도 쓰여 기간 표시가 아니다. 표시가 없으면 nil.
  static func leadingRangeMarker(_ text: String) -> (rest: Substring, isRangeOnly: Bool)? {
    let trimmed = text.drop(while: \.isWhitespace)
    guard let first = trimmed.first else { return nil }
    if self.rangeSeparators.contains(first) {
      return (trimmed.dropFirst(), self.tildeSeparators.contains(first))
    }
    let word = self.englishRangeJoinWords.first { word in
      let after = trimmed.dropFirst(word.count)
      return trimmed.prefix(word.count).lowercased() == word
        && (after.first?.isWhitespace == true || self.startsWithDateShape(Substring(self.compact(after))))
    }
    return word.map { (trimmed.dropFirst($0.count), true) }
  }

  /// 줄 맨 앞이 이어짐 표시와 날짜 모양이면 이어짐 판정(`finished`·`confirmedExpiry` 가 쓴다). 표시가 없거나 날짜 모양이 아니면 nil.
  /// - 기간 표시(물결표·영문 잇는 말): `rangeEnd` 가 고르는 끝 날짜(`rangeEndMentionIndex`) 뒤 줄 끝까지(`textAfterRangeEnd`)가
  ///   기간 끝 말뿐이면 `.readable`. 그 사이에 다른 날짜나 글이 있으면("~ 2027.01.31까지 연장 신청 가능",
  ///   "~ 2027.03.31 (취소 2027.01.07까지)") `.unread`. 영문 날짜처럼 날짜로 읽지 못하면 `.readable` 로 넘겨 받는 쪽이 비운다.
  /// - 줄표: 글머리표로도 쓰여 날짜 표기뿐이어야 이어짐이다. 날짜로 읽은 것이 있으면 기간 표시와 같은 방법(같은 시각 판정)으로
  ///   끝 날짜 뒤를 보고, `년월일시분` 밖 글자가 남으면 nil(글머리표 안내문, "- 2027.01.31 pm25"). 날짜로 읽은 것이 없으면(영문 날짜)
  ///   `wordsAroundDate` 로 넓게 본다(이어짐이면 받는 쪽이 끝을 못 읽어 비우므로 넓게 받는 쪽이 안전하다).
  /// - Parameter base: 연도를 생략한 날짜의 기준(받는 쪽 `rangeEnd` 와 같은 값).
  static func leadingContinuation(_ text: String, base: LocalDate?) -> LeadingContinuation? {
    guard let marker = self.leadingRangeMarker(text), self.startsWithDateShape(Substring(self.compact(marker.rest)))
    else { return nil }
    let rest = String(marker.rest)
    let isDateOnly = { (words: String) in !words.contains { $0.isLetter && !"년월일시분".contains($0) } }
    guard !DateMention.mentions(in: rest).isEmpty else {
      return marker.isRangeOnly || isDateOnly(self.wordsAroundDate(rest)) ? .readable(marker.rest) : nil
    }
    let tail = self.textAfterRangeEnd(rest, base: base)
    if marker.isRangeOnly {
      return tail?.isEmpty == true ? .readable(marker.rest) : .unread
    }
    return tail.map(isDateOnly) == true ? .readable(marker.rest) : nil
  }

  /// `text` 에서 `rangeEnd` 가 고르는 끝 날짜 뒤 줄 끝까지를 요일 괄호·시각을 건너뛰고 기간 끝 말을 지운 나머지
  /// (공백 없이 소문자, `removingRangeEndWords`). 첫 날짜가 이어지지 않으면(앞에 글자) 끝이 없어 nil.
  private static func textAfterRangeEnd(_ text: String, base: LocalDate?) -> String? {
    let mentions = DateMention.mentions(in: text)
    let dates = mentions.indices.map { self.resolvedDate(at: $0, of: mentions, in: text, base: base) }
    guard let end = self.rangeEndMentionIndex(in: text, mentions: mentions, dates: dates) else { return nil }
    let tail = self
      .skippingWeekdayAndTime(self.compact(text[mentions[end.index].match.range.upperBound...]).lowercased())
    return self.removingRangeEndWords(String(tail))
  }

  /// 공백을 지운 텍스트가 날짜 모양으로 시작하는지: 날짜 앞부분("2027.10", "10월") 또는 영문 날짜 앞부분(`englishDatePrefix`).
  /// 숫자로만 시작하는 것("3,000", "1")은 아니다.
  static func startsWithDateShape(_ compact: Substring) -> Bool {
    compact.prefixMatch(of: self.datePrefixPattern) != nil || self.englishDatePrefix(compact)
  }

  /// 기간 끝 날짜 뒤에 붙어도 그 날짜가 기간의 끝인 말. 공백 없이 적는다. 임시 값이며 정확도 측정 작업에서 조정한다.
  static let rangeEndWords = ["까지", "만", "사용", "이용", "교환", "가능", "유효", "만료"]
  /// 기간 끝 말 뒤 줄 맨 끝에 붙는 존댓말·종결 어미. 임시 값이며 정확도 측정 작업에서 조정한다.
  static let sentenceEndings = ["합니다", "입니다", "이에요", "니다", "해요", "예요", "요", "함", "임"]

  /// 숫자 없이 홀로 쓴 시각 말. 긴 것부터 대조한다.
  private static let standaloneTimeWords = ["midnight", "a.m.", "p.m.", "noon", "오전", "오후", "자정", "정오", "am", "pm"]

  /// 공백 없이 소문자로 바꾼 텍스트에서 줄 맨 끝의 문장 부호와 어미 하나를 떼고(한 번만) 기간 끝 말을 지운 나머지.
  /// 어미는 끝에서만 떼므로 다른 글을 덮지 않는다("까지연장신청가능합니다" → "연장신청").
  /// 맨 앞의 홀로 쓴 시각 말 하나("오후", "pm")는 그 뒤가 기간 끝 말·어미뿐일 때만 뗀다. 뒤에 글이 남는 "pm25"·"amazon" 은
  /// 떼지 않는다(시각 말이 아니다).
  static func removingRangeEndWords(_ compact: String) -> String {
    let words = self.removingRangeEndWordsAndEnding(compact)
    guard !words.isEmpty, let timeWord = self.standaloneTimeWords.first(where: { compact.hasPrefix($0) }) else {
      return words
    }
    return self.removingRangeEndWordsAndEnding(String(compact.dropFirst(timeWord.count))).isEmpty ? "" : words
  }

  private static func removingRangeEndWordsAndEnding(_ compact: String) -> String {
    var text = Substring(compact)
    while let last = text.last, ".!。".contains(last) {
      text.removeLast()
    }
    if let ending = self.sentenceEndings.first(where: { text.hasSuffix($0) }) {
      text.removeLast(ending.count)
    }
    var words = ""
    while let character = text.first {
      if let word = self.rangeEndWords.sorted(by: { $0.count > $1.count }).first(where: { text.hasPrefix($0) }) {
        text = text.dropFirst(word.count)
        continue
      }
      words.append(character)
      text = text.dropFirst()
    }
    return words
  }

  /// 줄표 뒤 텍스트에서 날짜 표기에 붙는 말을 지운 글(공백 없이 소문자): 줄 맨 끝 어미·기간 끝 말(`removingRangeEndWords`),
  /// 요일 괄호, 숫자·점과 붙은 영문 월 이름, 숫자 뒤 서수(st·nd·rd·th), 숫자와 붙은 am·pm, 시각 말(자정·정오·오전·오후·midnight·noon).
  /// 남은 글자가 `년월일시분` 밖이면 날짜 표기뿐이 아니다("game" 의 "am" 은 숫자와 붙지 않아 글자다).
  /// 시각을 패턴 없이 넓게 지우므로 영문 날짜 줄(날짜로 읽은 것이 없을 때, `leadingContinuation`)에서만 쓴다.
  static func wordsAroundDate(_ text: some StringProtocol) -> String {
    var source = self.removingRangeEndWords(self.compact(text).lowercased()).replacing(#/\([^)]{1,3}\)/#, with: "")
    for timeWord in ["자정", "정오", "오전", "오후", "midnight", "noon"] {
      source = source.replacing(timeWord, with: "")
    }
    var words = ""
    var rest = Substring(source)
    while let character = rest.first {
      if let word = (self.englishMonthNames + ["a.m.", "p.m.", "am", "pm"]).first(where: { rest.hasPrefix($0) }) {
        let neighbors = [words.last, rest.dropFirst(word.count).first]
        if neighbors.contains(where: { $0?.isNumber == true || $0 == "." }) {
          rest = rest.dropFirst(word.count)
          continue
        }
      }
      words.append(character)
      rest = rest.dropFirst()
      if character.isNumber, let ordinal = ["st", "nd", "rd", "th"].first(where: { rest.hasPrefix($0) }) {
        rest = rest.dropFirst(ordinal.count)
      }
    }
    return words
  }

  /// "까지"가 붙은 기한이 여럿이면("주문 취소는 2026.10.20까지") 가장 늦은 것을 쓴다. 만료일은 기프티콘의 마지막 기한이다.
  /// 연도를 생략한 기한은 기준일 뒤로 보정돼 실제보다 늦어질 수 있다("이벤트 응모 10월 1일까지" 가 다음 해 10월 1일).
  /// 그래서 연도를 모르는 기한이 연도를 아는 기한보다 늦으면 어느 쪽이 만료일인지 알 수 없어 비운다.
  /// 앞 줄에서 시작한 기간(`notBefore`)을 기준으로 연도를 정한 기한은 연도를 아는 것으로 본다.
  /// 그 기간의 끝을 찾지 못해 여기 왔으면, 날짜 앞에 글이 없는 기한 줄("2026.12.31 까지")만 그 끝으로 본다
  /// (기간 시작 뒤의 "주문 취소는 2026.10.07까지" 를 만료일로 쓰지 않는다).
  static func latestDeadline(
    in lines: [RecognizedTextLine],
    base: LocalDate?,
    notBefore: LocalDate?
  ) -> LocalDate? {
    let deadlines = lines.flatMap { line in
      let mentions = DateMention.mentions(in: line.text)
      return mentions.indices
        .filter { self.hasExpirySuffix(after: mentions[$0].match, in: line.text) }
        .filter { notBefore == nil || !self.hasTextBeforeRange(ending: $0, of: mentions, in: line.text) }
        .compactMap { index in
          self.resolvedDate(at: index, of: mentions, in: line.text, base: base).map { date in
            (date: date, knowsYear: notBefore != nil || self.yearAnchor(at: index, of: mentions, in: line.text) != nil)
          }
        }
    }
    .filter { deadline in notBefore.map { deadline.date >= $0 } ?? true }
    let latestWithYear = deadlines.filter(\.knowsYear).map(\.date).max()
    let latestWithoutYear = deadlines.filter { !$0.knowsYear }.map(\.date).max()
    guard let latestWithYear else { return latestWithoutYear }
    return latestWithoutYear.map { $0 > latestWithYear } == true ? nil : latestWithYear
  }

  /// 공백을 지운 텍스트 앞의 요일 괄호("(목)")와 시각을 건너뛴다. 시각은 대소문자를 무시하고 "23:59", "11:59PM", "pm11:59",
  /// "오후11:59", "a.m.12:00", 분 없는 "12AM"·"11 PM"·"PM 11", "23시 59분", "오후 11시", "자정"·"정오"·"midnight"·"noon" 이다.
  /// 뒤에 붙은 분 없는 AM·PM("12AM", "11 PM")은 시 1~12 이고 뒤에 영문자가 오면 아니다("2 amazon"). 앞에 붙은 AM·PM("PM 11")은
  /// 시 1~12 이고 시 뒤에 숫자·점·콜론·슬래시가 오면 아니다("pm25", "pm2.5", "pm 2026.12.31"). 줄표는 그 뒤가 날짜일 때만
  /// 시각이다("AM 9 - 2026.12.31" 은 시각, 월.일 "PM 12-31" 은 아니다).
  static func skippingWeekdayAndTime(_ compact: some StringProtocol) -> Substring {
    var rest = Substring(compact)
    while let prefix = rest.prefixMatch(of: self.weekdayOrTimePattern) {
      rest = rest[prefix.range.upperBound...]
    }
    return rest
  }

  private static var weekdayOrTimePattern: Regex<Substring> {
    #/
      (?i)\([^)]{1,3}\)
      | (?:오전|오후|am|pm|a\.m\.|p\.m\.)?\d{1,2}(?::\d{2}){1,2}(?:(?:am|pm|a\.m\.|p\.m\.)(?![a-z]))?
      | (?:1[0-2]|0?[1-9])(?:am|pm|a\.m\.|p\.m\.)(?![a-z])
      | (?:am|pm|a\.m\.|p\.m\.)(?:1[0-2]|0?[1-9])(?![\d.:/])
        (?!-(?!\d{1,4}[./\-년]\d{1,2}|\d{1,2}월|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))
      | (?:오전|오후)?\d{1,2}시(?:\d{1,2}분)?
      | 자정 | 정오 | midnight | noon
    /#
  }

  /// 이웃 줄이 이어진 기간일 때의 판정(`leadingContinuation`).
  enum LeadingContinuation: Equatable {
    /// 이어진 기간의 끝을 읽을 텍스트(표시 뒤). 받는 쪽이 `rangeEnd` 로 끝을 읽는다.
    case readable(Substring)
    /// 이어진 기간인데 끝 날짜 뒤에 기간 끝 말이 아닌 글이 있어 끝으로 믿을 수 없다. 규칙은 비우고 모델은 받지 않는다.
    case unread
  }

  enum RangeEnd: Equatable {
    /// 만료일로 볼 날짜. 기간이면 끝 날짜다. `isEndFixed` 는 "까지" 날짜나 기간의 끝이라 끝이 이미 정해졌는지다
    /// (아니면 이웃 줄에서 기간이 이어질 수 있다).
    case date(LocalDate, isEndFixed: Bool)
    /// 이어짐 기호·"부터"·잇는 말로 끝나 끝 날짜가 다음 줄에 있다. 시작 날짜는 그 앞 날짜다(연도가 없거나 날짜가 없으면 nil).
    case continued(start: LocalDate?)
    /// 날짜가 있지만 만료일로 정하지 못했다(기간의 끝을 읽지 못함, 다른 항목의 날짜 등). 만료일을 알 수 없으므로 기간 시작도 두지 않는다.
    case unread
    /// 날짜가 없다.
    case notFound

    var rangeStart: LocalDate? {
      switch self {
      case let .continued(start):
        start
      case .date, .unread, .notFound:
        nil
      }
    }

    var isContinued: Bool {
      if case .continued = self {
        true
      } else {
        false
      }
    }

    var isUnread: Bool {
      if case .unread = self {
        true
      } else {
        false
      }
    }
  }
}
