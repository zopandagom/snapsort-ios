import Foundation

/// 텍스트에 적힌 날짜 하나 (docs/ARCHITECTURE.md §4 기프티콘 추출). 연도를 생략할 수 있어 기간의 다른 날짜나 기준일을 보고 `LocalDate` 로 정한다.
struct DateMention {
  let match: Regex<AnyRegexOutput>.Match
  /// 적힌 연도. 두 자리 연도는 2000년대로 본다. 생략했으면 nil.
  let year: Int?
  let month: Int
  let day: Int

  /// 연도를 생략한 날짜를 찾을 때 기준 연도부터 살펴보는 햇수. 2월 29일도 다음 윤년까지 찾는다.
  private static let maximumYearSearch = 8

  /// 원문에서 날짜 모양("2026.12.31", "26-12-31", "2026. 12. 31", "2026년 12월 31일", "12월 31일")을 찾는다. 적힌 순서다.
  /// 날짜 안의 공백은 허용하고, 앞뒤가 숫자에 바로 붙은 것(쿠폰 번호처럼 더 긴 숫자열의 일부)은 건너뛴다.
  /// 공백은 경계로 남으므로 "2026.12.31 23:59" 의 시각은 날짜를 막지 않는다.
  static func mentions(in text: String) -> [DateMention] {
    // "2026년 12월 31일까지"처럼 뒤에 붙은 말을 보도록 "일"까지 날짜에 넣는다. "일"이 없으면 뒤 공백은 넣지 않는다.
    let pattern =
      #/(\d{4}|\d{2})\s*[./\-년]\s*(\d{1,2})\s*[./\-월]\s*(\d{1,2})(?:\s*일)?|(\d{1,2})\s*월\s*(\d{1,2})\s*일/#
    return text.matches(of: Regex<AnyRegexOutput>(pattern))
      .filter { match in
        let before = match.range.lowerBound == text.startIndex
          ? nil : text[text.index(before: match.range.lowerBound)]
        let after = match.range.upperBound == text.endIndex ? nil : text[match.range.upperBound]
        return before?.isNumber != true && after?.isNumber != true
      }
      .compactMap(DateMention.init)
  }

  init?(_ match: Regex<AnyRegexOutput>.Match) {
    let output = match.output
    func number(_ index: Int) -> Int? {
      output[index].substring.flatMap { Int($0) }
    }
    if let year = number(1), let month = number(2), let day = number(3) {
      // 두 자리 연도는 "26.12.31" 처럼 같은 구분 기호로 붙여 쓴 것과 "26년 12월 31일" 만 날짜로 본다
      // ("01.01 - 12.31" 을 2001-01-12 로 읽지 않는다).
      if year < 100, !Self.isUnambiguousTwoDigitYearDate(match.output[0].substring ?? "") {
        return nil
      }
      (self.year, self.month, self.day) = (year < 100 ? 2000 + year : year, month, day)
    } else if let month = number(4), let day = number(5) {
      (self.year, self.month, self.day) = (nil, month, day)
    } else {
      return nil
    }
    self.match = match
  }

  /// 두 자리 연도 날짜로 읽어도 되는지: 공백 없이 같은 구분 기호 둘로 이었거나("26.12.31") "년"·"월"을 모두 적었다("26년 12월 31일").
  private static func isUnambiguousTwoDigitYearDate(_ text: Substring) -> Bool {
    if text.contains("년"), text.contains("월") {
      return true
    }
    let separators = text.filter { !$0.isNumber && $0 != "일" }
    return separators.count == 2 && Set(separators).count == 1
  }

  /// 연도가 있으면 그 날짜, 없으면 `base` 이후(같은 날 포함) 처음 오는 그 날짜. 달력에 없거나 연도도 `base` 도 없으면 nil.
  func resolved(onOrAfter base: LocalDate?) -> LocalDate? {
    if let year {
      return LocalDate(year: year, month: self.month, day: self.day)
    }
    guard let base else { return nil }
    return (base.year ... base.year + Self.maximumYearSearch).lazy
      .compactMap { LocalDate(year: $0, month: self.month, day: self.day) }
      .first { $0 >= base }
  }
}
