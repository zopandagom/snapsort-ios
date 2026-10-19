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

  enum RangeEnd: Equatable {
    /// 만료일로 볼 날짜. 기간이면 끝 날짜다. `isEndFixed` 는 "까지" 날짜나 기간의 끝이라 끝이 이미 정해졌는지다
    /// (아니면 이웃 줄에서 기간이 이어질 수 있다).
    case date(LocalDate, isEndFixed: Bool)
    /// 이어짐 기호나 "부터"로 끝나 끝 날짜가 다음 줄에 있다. 시작 날짜는 그 앞 날짜다(연도가 없거나 날짜가 없으면 nil).
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
