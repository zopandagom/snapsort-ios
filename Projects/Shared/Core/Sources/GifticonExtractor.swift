import CoreGraphics
import Foundation

/// 기프티콘 이미지에서 읽은 정보. 찾지 못한 값은 nil 이다.
public struct GifticonInfo: Sendable, Hashable {
  public let expiryDate: LocalDate?
  /// 교환처 라벨 옆이나 아래에 적힌 텍스트(예: "스타벅스"). 브랜드 이름으로 정규화하지 않는다.
  public let redemptionPlace: String?

  public init(expiryDate: LocalDate?, redemptionPlace: String?) {
    self.expiryDate = expiryDate
    self.redemptionPlace = redemptionPlace
  }
}

/// 기프티콘 이미지의 OCR 줄에서 만료일과 교환처를 찾는 규칙 (docs/ARCHITECTURE.md §4).
/// 줄 맨 앞의 라벨("유효기간", "교환처")을 찾고 그 줄의 라벨 뒤, 없으면 라벨 오른쪽 같은 높이나 바로 아래 줄의 값을 읽는다.
/// 라벨 줄과 값 줄에는 같은 규칙(날짜 찾기, 기간 이어짐)을 쓴다.
/// OCR 이 "유 효 기 간"처럼 띄워 읽어도 찾도록 라벨은 공백을 무시하고 대조한다. 날짜와 그 앞뒤 경계는 원문에서 판단한다
/// (공백을 지우면 "2026.12.31 23:59" 의 날짜와 시각이 붙어 긴 숫자열처럼 보인다).
/// 라벨은 `ClassificationRules` 키워드 표와 따로 둔다(`scripts/mask-samples.py` 는 그 표만 읽는다).
/// 결과에 사진에서 읽은 텍스트가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public enum GifticonExtractor {
  /// 추출 규칙 버전. 규칙을 바꿔 같은 줄에서 다른 값이 나올 수 있으면 올린다.
  /// 저장소가 이 버전으로 추출하지 않은 행을 다시 추출 대상으로 돌려준다.
  /// 언어 모델 보강의 확인 규칙(`GifticonExtractor+Model.swift`)은 이 버전이 아니라 `modelFillVersion` 으로 센다.
  /// 2: 기간의 끝을 놓쳐 시작을 쓰던 경로를 고쳤다(읽지 못한 끝은 비운다: 기호·잇는 말·"부터" 뒤 영문 날짜, "부터" 뒤 날짜 아닌 글,
  /// 기간 표시 이웃 줄 날짜 뒤 다른 글. 끝을 읽는다: 영문·한국어 잇는 말 "to"·"에서", 이웃 줄 영문 날짜 앞부분과 공백 없는
  /// "to2026.12.31", AM/PM·오전/오후 시각). 상세는 docs/ARCHITECTURE.md §4 기프티콘 추출 행.
  public static let rulesVersion = 2

  /// 만료일 라벨. 공백 없이 소문자로 적는다.
  static let expiryLabels = ["유효기간", "유효기한", "사용기한", "사용기간", "만료일", "만료일자"]
  /// 교환처 라벨. 공백 없이 소문자로 적는다.
  static let redemptionPlaceLabels = ["교환처", "사용처", "교환매장", "사용매장"]
  /// 기간의 두 날짜를 잇는 기호. 줄이 이 기호로 끝나면 기간이 다음 줄로 넘어간 것으로 본다.
  /// OCR 이 물결표를 전각·수학 기호·파형 대시나 줄표로 읽어도 맞도록 함께 둔다.
  static let rangeSeparators: Set<Character> = ["~", "～", "∼", "〜", "-", "–", "—"]
  /// 라벨 줄에서 만료일을 못 찾았을 때 만료일로 보는, 날짜 바로 뒤에 붙는 말(예: "2026.12.31까지").
  static let expirySuffix = "까지"
  /// 기간의 시작 날짜 뒤에 붙어 다음 날짜와 잇는 말(예: "2026.01.01부터 2026.12.31").
  static let rangeStartSuffix = "부터"
  /// 라벨 바로 뒤에 붙으면 라벨이 아니라 안내문의 주어·목적어로 보는 조사.
  static let labelParticles: Set<Character> = ["이", "가", "은", "는", "을", "를", "의", "에"]
  /// 라벨 바로 아래 줄로 보는, 라벨 아래 끝과 다음 줄 위 끝 사이 간격의 최대치(라벨 높이의 배수).
  static let maximumLineGapRatio: CGFloat = 1.5

  /// - Parameters:
  ///   - textLines: 기프티콘으로 분류한 이미지의 OCR 줄.
  ///   - referenceDate: 이미지 생성 시각. 연도를 생략한 만료일("12월 31일")은 기간 안에 연도가 적힌 앞 날짜가 있으면 그 날짜,
  ///     앞 줄에서 시작한 기간이 있으면 그 시작일, 둘 다 없으면 이 날 이후 처음 오는 그 날짜로 본다.
  ///     기준이 모두 nil 이면 연도를 생략한 날짜는 쓰지 않는다.
  ///   - calendar: `referenceDate` 의 날짜를 정하는 달력. 앱은 기기 달력을 넘긴다.
  public static func extract(
    from textLines: [RecognizedTextLine],
    referenceDate: Date?,
    calendar: Calendar
  ) -> GifticonInfo {
    let reference = referenceDate.map { LocalDate($0, calendar: calendar) }
    return GifticonInfo(
      expiryDate: self.expiryDate(in: textLines, reference: reference),
      redemptionPlace: self.redemptionPlace(in: textLines)
    )
  }

  /// 만료일 라벨 줄을 OCR 순서로 보며(라벨 줄, 다음 줄로 넘어가면 값 줄) 만료일을 처음 찾은 날짜(`rangeEnd`).
  /// 기간("2026.01.01 ~ 2026.12.31")이면 끝 날짜를 쓴다.
  /// 어느 라벨 줄에서도 못 찾으면 날짜 뒤에 "까지"가 붙은 날짜 중 가장 늦은 것을 쓴다. 단 라벨 줄·값 줄에 날짜가 있는데 끝을 읽지
  /// 못했거나 날짜 없는 상대 기간("구매일로부터 1년")만 있으면 쓰지 않는다. 라벨도 "까지"도 없는 날짜(발행일·주문일)는 쓰지 않는다.
  private static func expiryDate(in lines: [RecognizedTextLine], reference: LocalDate?) -> LocalDate? {
    // 라벨 줄이나 그 값 줄에서 시작한 기간의 시작 날짜 중 가장 늦은 것. 끝 날짜를 끝내 못 찾아도 만료일은 이보다 이를 수 없다.
    var rangeStart: LocalDate?
    func noteStart(_ start: LocalDate?) {
      guard let start else { return }
      rangeStart = max(rangeStart ?? start, start)
    }
    // 앞 라벨 줄에서 만료일을 알 수 없게 됐는지(날짜나 설명이 있는데 정하지 못함). 그러면 뒤 라벨 줄의 날짜도 "까지" 기한도
    // 만료일인지 알 수 없다. 틀린 만료일보다 비워 둔다.
    var foundUnreadDate = false
    // 찾은 날짜를 앞 라벨 줄이 남긴 조건(끝을 못 읽음, 기간 시작)과 맞춰 본다.
    func accepted(_ date: LocalDate) -> LocalDate? {
      !foundUnreadDate && (rangeStart.map { date >= $0 } ?? true) ? date : nil
    }
    // 찾은 날짜의 줄 오른쪽이나 아래 줄이 이어짐 표시(이어짐 기호 또는 영문 잇는 말)와 날짜 모양으로 시작하면(`leadingContinuation`,
    // "2026.10.18" / "~ 2027.10.17") 기간이 줄바꿈으로 넘어간 것이다. 찾은 날짜는 기간 시작이므로 그 줄의 끝 날짜를 쓰고, 끝을 못 읽으면
    // 만료일을 비운다. 기간 표시(물결표·영문 잇는 말)는 날짜 뒤에 기간 끝 말만, 줄표는 날짜 표기뿐이어야 하고, 기간 표시 뒤에
    // 다른 글이 있으면 끝을 믿을 수 없어 비운다.
    // 끝이 이미 정해진 날짜("까지" 날짜, 기간의 끝, 앞 줄에서 넘어온 기간의 끝)는 이웃 줄을 보지 않는다
    // ("유효기간 2026.12.31까지" 아래 "- 2027.03.31" 은 이어진 기간이 아니다).
    func finished(_ date: LocalDate, isEndFixed: Bool, on line: RecognizedTextLine) -> LocalDate? {
      if isEndFixed {
        return accepted(date)
      }
      let neighbors = self.neighborLines(of: line, in: lines)
      guard let continuation = [neighbors.sameRow, neighbors.below].lazy
        .compactMap({ $0.flatMap { self.leadingContinuation($0.text, base: date) } }).first
      else { return accepted(date) }
      guard case let .readable(rest) = continuation,
            case let .date(end, _) = self.rangeEnd(in: rest, reference: reference, notBefore: date)
      else { return nil }
      return accepted(end)
    }
    for (label, rest) in self.labeledLines(lines, labels: self.expiryLabels) {
      // 앞 라벨 줄에서 시작한 기간이 있으면 이 줄의 날짜도 그 이후다(연도를 생략한 날짜의 기준도 된다).
      let labelEnd = self.rangeEnd(in: rest, reference: reference, notBefore: rangeStart)
      switch labelEnd {
      case let .date(date, isEndFixed):
        return finished(date, isEndFixed: isEndFixed, on: label)
      case .unread:
        // 라벨 뒤에 날짜가 있는데 만료일을 정하지 못했다("유효기간 2026.01.01 ~ 12.31"). 아래 줄은 그 값이 아니다.
        break
      case .notFound where self.compact(rest).contains(where: \.isLetter):
        // 라벨 뒤에 날짜 없는 글이 있다. 아래 줄의 날짜(발행일)는 그 값이 아니다.
        // 숫자가 든 상대 기간("유효기간 구매일로부터 1년")이면 다른 기한도 만료일이 아니다. 숫자 없는 안내문
        // ("유효기간 만료 후 환불 불가")은 뒤 라벨 줄과 "까지" 기한을 막지 않는다.
        foundUnreadDate = foundUnreadDate || self.isRelativePeriod(rest)
      case .continued, .notFound:
        // 라벨 뒤가 비었거나 기간이 줄을 넘어가면("유효기간 2026.01.01 ~" / "2026.12.31") 값 줄을 같은 규칙으로 읽는다.
        // 넘어간 기간의 끝 날짜는 시작 날짜보다 이를 수 없다. 값 줄도 이어지면 끝 날짜를 못 찾은 것이다.
        // 어느 경우든 시작 날짜를 만료일로 쓰지 않는다(실제보다 이른 알림이 된다).
        // 오른쪽 같은 높이 줄에 날짜가 없으면("D-365") 아래 줄을 본다.
        let neighbors = self.neighborLines(of: label, in: lines)
        let candidates = [neighbors.sameRow, neighbors.below].compactMap(\.self).map { value in
          (value, self.rangeEnd(in: value.text, reference: reference, notBefore: labelEnd.rangeStart ?? rangeStart))
        }
        if let (value, valueEnd) = candidates.first(where: { $0.1 != .notFound }) ?? candidates.first {
          if case let .date(date, isEndFixed) = valueEnd {
            return finished(date, isEndFixed: isEndFixed || labelEnd.isContinued, on: value)
          }
          noteStart(valueEnd.rangeStart)
          // 값 줄이 날짜 없는 상대 기간이어도("구매일로부터 1년") 라벨 뒤 상대 기간과 같이 만료일을 알 수 없다.
          foundUnreadDate = foundUnreadDate || valueEnd
            .isUnread || (valueEnd == .notFound && self.isRelativePeriod(value.text))
        }
      }
      noteStart(labelEnd.rangeStart)
      foundUnreadDate = foundUnreadDate || labelEnd.isUnread
    }
    // 라벨의 기간 끝을 읽지 못했으면("유효기간 2026.01.01 ~ 12.31 (취소 2026.01.07까지)") 다른 기한을 만료일로 쓰지 않는다.
    guard !foundUnreadDate else { return nil }
    return self.latestDeadline(in: lines, base: rangeStart ?? reference, notBefore: rangeStart)
  }

  /// 날짜 바로 뒤에(요일 괄호 "(목)"·시각 "23:59" 는 건너뛴다) "까지"가 붙었는지.
  static func hasExpirySuffix(after match: DateMatch, in text: String) -> Bool {
    self.skippingWeekdayAndTime(self.compact(text[match.range.upperBound...])).hasPrefix(self.expirySuffix)
  }

  /// 두 날짜 사이가 요일 괄호·시각을 빼면 기간을 잇는 말뿐인지("2026.01.01 00:00 ~ 2026.12.31", "2026.01.01부터 2026.12.31").
  /// 잇는 말은 "부터"(있으면 맨 앞)와 이어짐 기호 하나 또는 잇는 말 단어 하나(`rangeJoinWords`, "to"·"에서")이고,
  /// 둘 다 없이 공백만 있어도 OCR 이 물결표를 빼먹은 기간으로 본다. 사이에 다른 글자("주문일")가 있으면 기간이 아니다.
  /// 시각은 사이 글만으로도, 뒤 날짜까지 붙여서도 건너뛰어 본다(줄표 앞 시각 "AM 9 - 2026.12.31" 은 줄표 뒤가 날짜여야 시각이다).
  static func isRange(from start: DateMatch, to end: DateMatch, in text: String) -> Bool {
    let gap = self.compact(text[start.range.upperBound ..< end.range.lowerBound])
    let endText = self.compact(text[end.range])
    let withEnd = self.rangeJoiner(gap + endText)
    let joiners = [self.rangeJoiner(gap)] + (withEnd.hasSuffix(endText) ? [withEnd.dropLast(endText.count)] : [])
    return joiners.contains { between in
      between.isEmpty || between.count == 1 && between.first.map(self.rangeSeparators.contains) == true
        || self.rangeJoinWords.contains(between.lowercased())
    }
  }

  /// 날짜 뒤가 기간을 잇는 말과 날짜 모양(`startsWithUnreadDate`)으로 시작하는지("2026.01.01 ~ 12.31", "2026.01.01 ~ Dec 31, 2026").
  /// 끝 날짜를 날짜로 읽지 못한 기간이다. "부터" 뒤에 무엇이든 이어지면("2026.01.01부터 12.31까지", "2026.10.01부터 사용 가능")
  /// 기간 시작을 밝힌 것이라 끝 날짜를 읽지 못한 기간으로 본다(줄이 "부터"로 끝나면 `continuesOnNextLine` 이 먼저 본다).
  private static func continuesToUnreadDate(after match: DateMatch, in text: String) -> Bool {
    let afterDate = self.skippingWeekdayAndTime(self.compact(text[match.range.upperBound...]))
    let rest = self.rangeJoiner(self.compact(text[match.range.upperBound...]))
    if afterDate.hasPrefix(self.rangeStartSuffix), afterDate.count > self.rangeStartSuffix.count {
      return true
    }
    // 물결표까지 빠진 "2026.01.01 12.31" 의 월.일도 읽지 못한 끝 날짜다("2026.12.31 1매" 의 수량은 아니다).
    if afterDate.prefixMatch(of: self.monthDayPattern) != nil {
      return true
    }
    if rest.first.map(self.rangeSeparators.contains) == true {
      return self.startsWithUnreadDate(rest.dropFirst())
    }
    // 잇는 말 단어 뒤도 같다("2026.01.01 to Dec 31, 2026"). "total 3" 처럼 뒤가 날짜 모양이 아니면 아니다.
    let lowercased = rest.lowercased()
    return self.rangeJoinWords.contains { word in
      lowercased.hasPrefix(word) && self.startsWithUnreadDate(rest.dropFirst(word.count))
    }
  }

  /// 연도 없는 월.일("12.31", "12/31"). 뒤에 숫자가 이어지면 아니다.
  private static var monthDayPattern: Regex<Substring> { #/\d{1,2}[./\-]\d{1,2}(?!\d)/# }
  /// 날짜 표기의 앞부분("2027.10", "27.10", "2027년 10", "10월").
  static var datePrefixPattern: Regex<Substring> { #/\d{1,4}[./\-년]\d{1,2}|\d{1,2}월/# }

  /// 날짜 없이 숫자가 든 글인지(상대 기간 "구매일로부터 1년", "발급일로부터 90일").
  private static func isRelativePeriod(_ text: some StringProtocol) -> Bool {
    let compact = self.compact(text)
    return compact.contains(where: \.isLetter) && compact.contains(where: \.isNumber)
  }

  /// 줄이 기간을 잇는 말로 끝나 끝 날짜가 다음 줄에 있는지("유효기간 2026.01.01 ~", "유효기간 2026.01.01부터", "유효기간 2026.01.01 to").
  private static func continuesOnNextLine(_ text: String, after lastMention: DateMention?) -> Bool {
    if let last = text.trimmingCharacters(in: .whitespaces).last, self.rangeSeparators.contains(last) {
      return true
    }
    guard let end = lastMention?.match.range.upperBound else { return false }
    let rest = self.skippingWeekdayAndTime(self.compact(text[end...]))
    return rest == self.rangeStartSuffix || self.rangeJoinWords.contains(rest.lowercased())
  }

  /// 공백을 지운 날짜 뒤 텍스트에서 요일 괄호·시각과 "부터"를 건너뛴 나머지.
  private static func rangeJoiner(_ compact: String) -> Substring {
    let rest = self.skippingWeekdayAndTime(compact)
    return rest.hasPrefix(self.rangeStartSuffix) ? rest.dropFirst(self.rangeStartSuffix.count) : rest
  }

  /// 한 줄(라벨 뒤 텍스트나 값 줄)에서 만료일로 볼 날짜.
  /// - 첫 날짜(앞에 글자가 없어야 한다)부터 끊기지 않고 기간으로 이어진 "까지" 날짜가 있으면 그 날짜다. 같은 줄에 붙은 다른 항목의
  ///   기한("(취소 2026.01.07까지)", "(교환 2026.10.01~2026.10.07까지)")은 쓰지 않는다.
  /// - 없으면 첫 날짜이고, 기간을 잇는 말(`isRange`)로 다음 날짜와 이어진 기간이면 끝 날짜다.
  /// - 앞 날짜보다 이른 날짜는 기간의 끝도 "까지" 기한도 아니므로 잇지 않는다("2026.12.31 2026.10.01" 처럼 두 열을 한 줄로 읽은
  ///   주문일, "2026.12.31 2026.10.07까지" 의 다른 기한). 비교는 연도 보정까지 마친 날짜로 한다.
  /// - 첫 날짜 앞에 글자가 있으면 다른 항목의 날짜("주문일 2026.10.01")이므로 쓰지 않는다. 라벨 뒤 텍스트에서는 라벨이 이미 빠져 있다.
  /// - 기간의 끝을 읽지 못하면(줄이 이어짐 기호·"부터"·잇는 말("to" 등)로 끝남, "~ 12.31"·"부터 12.31까지" 처럼 날짜로 읽지 못함,
  ///   기호·잇는 말 뒤 영문 날짜("~ Dec 31, 2026"·"to Dec 31, 2026"), "부터" 뒤 날짜 아닌 글("부터 사용 가능"), 달력에 없는 날짜)
  ///   시작 날짜를 쓰지 않는다.
  /// - 연도를 생략한 끝 날짜는 기간 안의 연도가 적힌 앞 날짜 이후, 없으면 `notBefore`·기준일 이후 처음 오는 그 날짜다
  ///   ("10월 1일 ~ 12월 31일" 의 시작일을 기준일 뒤로 보내지 않는다).
  /// - Parameter notBefore: 앞 줄에서 시작한 기간의 시작 날짜. 이보다 이른 날짜는 끝 날짜가 아니다.
  static func rangeEnd(in text: some StringProtocol, reference: LocalDate?, notBefore: LocalDate?) -> RangeEnd {
    let text = String(text)
    let mentions = DateMention.mentions(in: text)
    let dates = mentions.indices.map { self.resolvedDate(at: $0, of: mentions, in: text, base: notBefore ?? reference) }
    if self.continuesOnNextLine(text, after: mentions.last) {
      // 한 줄일 때와 같은 규칙으로, 줄 안의 날짜가 첫 날짜(앞에 글자가 없다)부터 한 기간으로 이어질 때만 아래 줄에서 끝을 찾는다
      // ("유효기간 발행일 ~", "유효기간 2026.12.31 주문일 2026.10.01 ~", "유효기간 2026.12.31 2026.10.01 ~" 는 아니다).
      let isOneRange = mentions.isEmpty
        ? !self.compact(text).contains(where: \.isLetter)
        : mentions.indices.allSatisfy { self.isLinked($0, of: mentions, dates: dates, in: text) }
      let start = mentions.last.flatMap { $0.year == nil ? nil : $0.resolved(onOrAfter: nil) }
      return isOneRange ? .continued(start: start) : .unread
    }
    guard !mentions.isEmpty else { return .notFound }
    guard let pick = self.rangeEndMentionIndex(in: text, mentions: mentions, dates: dates) else { return .unread }
    let (endIndex, isSuffixed) = pick
    if !isSuffixed, self.continuesToUnreadDate(after: mentions[endIndex].match, in: text) {
      return .unread
    }
    guard let end = dates[endIndex], notBefore.map({ end >= $0 }) ?? true else {
      return .unread
    }
    return .date(end, isEndFixed: isSuffixed || endIndex > 0)
  }

  /// 한 줄에서 만료일로 볼 날짜의 위치(`rangeEnd` 와 이웃 줄 이어짐 판정 `leadingContinuation` 이 함께 쓴다).
  /// 첫 날짜부터 기간으로 이어진 "까지" 날짜가 있으면 그 날짜, 없으면 첫 날짜부터 기간으로 이어진 사슬의 마지막 날짜다.
  /// 첫 날짜가 이어지지 않으면(앞에 글자) nil. `dates` 는 `mentions` 를 연도 보정까지 마친 날짜다.
  static func rangeEndMentionIndex(
    in text: String,
    mentions: [DateMention],
    dates: [LocalDate?]
  ) -> (index: Int, isSuffixed: Bool)? {
    let isLinked = { (index: Int) in self.isLinked(index, of: mentions, dates: dates, in: text) }
    if let suffixed = mentions.indices
      .first(where: { self.hasExpirySuffix(after: mentions[$0].match, in: text) && (0 ... $0).allSatisfy(isLinked) })
    {
      return (suffixed, true)
    }
    guard !mentions.isEmpty, isLinked(0) else { return nil }
    var endIndex = 0
    while endIndex + 1 < mentions.count, isLinked(endIndex + 1) {
      endIndex += 1
    }
    return (endIndex, false)
  }

  /// `mentions[index]` 가 앞 날짜와 이어지는지. 첫 날짜는 앞에 글자가 없어야 하고, 뒤 날짜는 기간을 잇는 말로 이어지며
  /// 앞 날짜보다 이르지 않아야 한다.
  private static func isLinked(_ index: Int, of mentions: [DateMention], dates: [LocalDate?], in text: String) -> Bool {
    guard index > 0 else {
      return !self.compact(text[..<mentions[0].match.range.lowerBound]).contains(where: \.isLetter)
    }
    // 앞 날짜의 연도를 알 때만 비교한다. 연도를 생략한 기간 시작("10월 1일 ~ 12월 31일")은 기준일 뒤로 보정돼 순서를 알 수 없다.
    if let date = dates[index], let previous = dates[index - 1], date < previous,
       self.yearAnchor(at: index - 1, of: mentions, in: text) != nil
    {
      return false
    }
    return self.isRange(from: mentions[index - 1].match, to: mentions[index].match, in: text)
  }

  /// 교환처 라벨 줄을 OCR 순서로 보며 값을 처음 찾은 텍스트. 라벨 뒤 텍스트이고, 비었으면 라벨 오른쪽이나 아래 줄의 텍스트다.
  private static func redemptionPlace(in lines: [RecognizedTextLine]) -> String? {
    for (label, rest) in self.labeledLines(lines, labels: self.redemptionPlaceLabels) {
      if let place = self.cleanedValue(rest) ?? self.valueLine(of: label, in: lines)
        .flatMap({ self.cleanedValue($0.text) })
      {
        return place
      }
    }
    return nil
  }

  /// 라벨 중 하나로 시작하는 줄과, 그 줄에서 라벨 뒤의 원래 텍스트. OCR 순서대로다.
  static func labeledLines(
    _ lines: [RecognizedTextLine],
    labels: [String]
  ) -> [(line: RecognizedTextLine, rest: Substring)] {
    lines.compactMap { line in
      // 긴 라벨부터 대조해 "만료일자" 의 "자" 가 라벨 뒤 텍스트에 남지 않게 한다.
      labels.sorted { $0.count > $1.count }.lazy.compactMap { self.text(after: $0, in: line.text) }.first
        .map { (line, $0) }
    }
  }

  /// 줄 맨 앞(앞쪽 기호 "[", "■", "*" 와 공백은 건너뛴다)에 `label` 이 있으면 그 뒤의 원래 텍스트. 라벨 안의 공백은 무시한다.
  /// "제휴사(교환처) 사정에 따라…" 같은 안내문 속 라벨 단어는 라벨로 보지 않는다.
  static func text(after label: String, in text: String) -> Substring? {
    guard var index = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return nil }
    for expected in label {
      while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
      }
      guard index < text.endIndex, text[index].lowercased() == String(expected) else { return nil }
      index = text.index(after: index)
    }
    // 라벨 바로 뒤에 조사가 붙고 띄어 쓰면 안내문이다("유효기간이 지난 상품은", "교환처의 사정에 따라").
    // 띄어 쓰지 않았으면 OCR 이 공백을 빼먹은 값이다("사용처이마트").
    if index < text.endIndex, self.labelParticles.contains(text[index]),
       text[text.index(after: index)...].first?.isWhitespace ?? true
    {
      return nil
    }
    return text[index...]
  }

  /// 라벨 오른쪽 같은 높이의 줄, 없으면 라벨 바로 아래에서 가로로 겹치는 가장 가까운 줄.
  private static func valueLine(of label: RecognizedTextLine, in lines: [RecognizedTextLine]) -> RecognizedTextLine? {
    let neighbors = self.neighborLines(of: label, in: lines)
    return neighbors.sameRow ?? neighbors.below
  }

  /// 오른쪽 같은 높이의 가장 가까운 줄과, 바로 아래에서 가로로 겹치는 가장 가까운 줄.
  /// 다른 라벨로 시작하는 줄은 값이 아니므로 고르지 않는다(교환처가 로고라 읽은 글자가 없을 때 아래의 유효기간 줄을 고르지 않게).
  static func neighborLines(
    of line: RecognizedTextLine,
    in lines: [RecognizedTextLine]
  ) -> (sameRow: RecognizedTextLine?, below: RecognizedTextLine?) {
    let box = line.boundingBox
    let others = lines.filter { other in
      other != line && !(self.expiryLabels + self.redemptionPlaceLabels)
        .contains { self.text(after: $0, in: other.text) != nil }
    }
    let sameRow = others
      .filter { abs($0.boundingBox.midY - box.midY) < box.height / 2 && $0.boundingBox.minX >= box.midX }
      .min { $0.boundingBox.minX < $1.boundingBox.minX }
    let below = others
      .filter {
        $0.boundingBox.minY >= box.midY
          && $0.boundingBox.minY - box.maxY <= box.height * self.maximumLineGapRatio
          && $0.boundingBox.maxX > box.minX && $0.boundingBox.minX < box.maxX
      }
      .min { $0.boundingBox.minY < $1.boundingBox.minY }
    return (sameRow, below)
  }

  /// 앞뒤 공백과 구분 기호(":", "-", "|")를 뺀 값. 앞쪽의 닫는 괄호("[교환처] 편의점")도 뺀다. 비었으면 nil.
  static func cleanedValue(_ text: some StringProtocol) -> String? {
    let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：-|"))
    let value = text.drop { $0.isWhitespace || "])】）".contains($0) }.trimmingCharacters(in: separators)
    return value.isEmpty ? nil : value
  }

  typealias DateMatch = Regex<AnyRegexOutput>.Match

  static func compact(_ text: some StringProtocol) -> String {
    String(text.filter { !$0.isWhitespace })
  }
}
