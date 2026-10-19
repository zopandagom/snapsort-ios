import Foundation

/// 시간대 없이 연·월·일만 담는 그레고리력 날짜. 기프티콘 만료일처럼 이미지에 적힌 날짜를 담는다 (docs/ARCHITECTURE.md §4).
/// `Date` 로 두면 기기 시간대가 바뀔 때 날짜가 하루 밀리므로, 알림·화면에 쓸 때 기기 달력으로 바꾼다(`dateComponents`).
public struct LocalDate: Sendable, Hashable, Comparable {
  public let year: Int
  /// 1~12.
  public let month: Int
  /// 1~그달의 마지막 날.
  public let day: Int

  /// 달력에 없는 날짜(예: 2월 30일)면 nil.
  public init?(year: Int, month: Int, day: Int) {
    guard (1 ... 12).contains(month), (1 ... Self.numberOfDays(year: year, month: month)).contains(day) else {
      return nil
    }
    self.year = year
    self.month = month
    self.day = day
  }

  /// `date` 가 `calendar` 의 시간대에서 속한 그레고리력 날짜. 기기 달력이 일본력·불교력이어도 연도는 서기로 센다.
  public init(_ date: Date, calendar: Calendar) {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    self.year = gregorian.component(.year, from: date)
    self.month = gregorian.component(.month, from: date)
    self.day = gregorian.component(.day, from: date)
  }

  /// 연·월·일만 채운 그레고리력 날짜 구성 요소. 알림 시각처럼 시·분이 필요하면 받는 쪽이 더하고,
  /// `Date` 로 바꿀 때는 그레고리력 달력을 쓴다(기기 달력이 일본력이면 연도를 다르게 읽는다).
  public var dateComponents: DateComponents {
    DateComponents(year: self.year, month: self.month, day: self.day)
  }

  public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  private static func numberOfDays(year: Int, month: Int) -> Int {
    switch month {
    case 2:
      let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
      return isLeapYear ? 29 : 28
    case 4, 6, 9, 11:
      return 30
    default:
      return 31
    }
  }
}
