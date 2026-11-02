/// 기프티콘 만료일까지 남은 날 (docs/ARCHITECTURE.md §4 카테고리 화면). 만료일 당일까지 쓸 수 있다고 본다.
/// 문구("D-day", "D-3", "3일 지남")는 화면이 정한다.
public enum GifticonDue: Sendable, Hashable {
  /// 0 이면 오늘 만료(D-day), n 이면 D-n.
  case remaining(days: Int)
  /// 만료일이 지났다. n ≥ 1 일 지남.
  case expired(daysAgo: Int)

  /// - Parameter today: 기기 시간대의 오늘(`LocalDate(now, calendar:)`). 만료일은 시간대 없는 날짜라 일수만 센다.
  public init(expiryDate: LocalDate, today: LocalDate) {
    let days = today.days(until: expiryDate)
    self = days >= 0 ? .remaining(days: days) : .expired(daysAgo: -days)
  }

  /// 임박으로 보는 남은 날의 상한. D-day 부터 D-3 까지가 임박이다.
  public static let imminentDays = 3

  /// 곧 만료된다(D-day ~ D-`imminentDays`). 이미 만료됐으면 거짓이다. 화면이 배지를 강조(맥박)할 때 쓴다.
  public var isImminent: Bool {
    if case let .remaining(days) = self {
      return days <= Self.imminentDays
    }
    return false
  }
}
