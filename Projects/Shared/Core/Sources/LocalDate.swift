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

  /// `days` 일 뒤(음수면 앞)의 날짜. 그레고리력·시간대 없음으로 센다(월말·윤년 경계).
  public func addingDays(_ days: Int) -> LocalDate {
    Self(dayNumber: self.dayNumber + days)
  }

  /// `other` 까지의 일수. 그레고리력·시간대 없음으로 센다. `other` 가 앞이면 음수.
  public func days(until other: LocalDate) -> Int {
    other.dayNumber - self.dayNumber
  }

  /// 화면 표시용 시각: `calendar` 의 시간대에서 그날 12:00. 자정이 없는 시간대 전환일에도 날짜가 밀리지 않게 정오로 둔다.
  /// 받는 쪽은 같은 시간대로 형식화한다(시간대 차이가 12시간 미만이면 다른 시간대로 형식화해도 같은 날짜다).
  public func noon(in calendar: Calendar) -> Date? {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    var components = self.dateComponents
    components.hour = 12
    return gregorian.date(from: components)
  }

  public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  /// 1970-01-01 부터 센 일련 일수. 실패 경로가 없도록 `Calendar` 대신 그레고리력 정수 공식으로 센다
  /// (3월을 한 해의 시작으로 보아 윤일이 해 끝에 오게 하고, 400년 주기로 나눈다).
  private var dayNumber: Int {
    let year = self.month <= 2 ? self.year - 1 : self.year
    let era = (year >= 0 ? year : year - 399) / 400
    let yearOfEra = year - era * 400
    let dayOfYear = (153 * (self.month + (self.month > 2 ? -3 : 9)) + 2) / 5 + self.day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  /// `dayNumber` 의 역변환.
  private init(dayNumber: Int) {
    let shifted = dayNumber + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    self.year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    self.month = month
    self.day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
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
