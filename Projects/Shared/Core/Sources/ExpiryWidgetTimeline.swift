import Foundation

/// 만료 임박 위젯이 하루 동안 보일 값 (docs/ARCHITECTURE.md §4 만료 임박 위젯). 개수와 날짜만 담는다(교환처·식별자 없음).
public struct ExpiryWidgetSummary: Sendable, Hashable {
  /// 이 요약이 보이는 날.
  public let date: LocalDate
  /// `date` ~ `date + windowDays` 에 만료되는(양끝 포함) 기프티콘 수. 같은 `imageID` 는 한 번 센다.
  public let count: Int
  /// 가장 가까운 만료일까지 남은 날. 0 이면 D-day. `count` 가 0 이면 nil.
  public let nearestDaysLeft: Int?
  /// 추출 대기 기프티콘이 있어 값이 바뀔 수 있다("확인 중").
  public let isChecking: Bool

  public init(date: LocalDate, count: Int, nearestDaysLeft: Int?, isChecking: Bool) {
    self.date = date
    self.count = count
    self.nearestDaysLeft = nearestDaysLeft
    self.isChecking = isChecking
  }
}

/// 만료 임박 위젯의 타임라인 규칙. 위젯(Provider)과 갱신 요청 중복 제거(`LibraryModel`)가 같은 요약을 쓴다.
/// 문구는 두지 않는다(Core 는 문구를 갖지 않는다).
public enum ExpiryWidgetTimeline {
  /// 위젯 kind. 바꾸면 사용자가 놓은 위젯이 사라지므로 바꾸지 않는다.
  public static let kind = "ExpiryWidget"
  /// 오늘부터 며칠 뒤 만료까지 세는지. 만료 알림의 7일 전과 같은 상수.
  public static let windowDays = ExpiryReminderPlanner.weekBeforeDays
  /// 오늘 뒤 며칠치 요약을 한 타임라인에 미리 넣는지.
  public static let horizonDays = 7

  /// 오늘~오늘+`horizonDays` 의 날마다 요약(`horizonDays + 1` 개, 날짜 오름차순).
  /// 만료일이 그날보다 앞인 것은 빠지고(어제 만료는 오늘 요약에 없다), 그날 만료는 D-day 로 든다(`GifticonDue` 와 같은 경계).
  /// - Parameters:
  ///   - expiries: 미사용 기프티콘의 만료일. 같은 `imageID` 가 여러 번 오면 한 번만 센다(마지막 값).
  ///   - isChecking: 추출 대기가 있는지. 모든 날의 요약에 그대로 넣는다.
  ///   - today: 기기 시간대의 오늘(`LocalDate(now, calendar:)`).
  public static func summaries(
    for expiries: [GifticonExpiry],
    isChecking: Bool,
    today: LocalDate
  ) -> [ExpiryWidgetSummary] {
    let expiryDates = Dictionary(expiries.map { ($0.imageID, $0.expiryDate) }, uniquingKeysWith: { _, last in last })
      .values
    return (0 ... Self.horizonDays).map { offset in
      let date = today.addingDays(offset)
      let daysLeft = expiryDates
        .map { date.days(until: $0) }
        .filter { (0 ... Self.windowDays).contains($0) }
      return ExpiryWidgetSummary(
        date: date,
        count: daysLeft.count,
        nearestDaysLeft: daysLeft.min(),
        isChecking: isChecking
      )
    }
  }

  /// `date` 가 시작하는 시각(`calendar` 의 시간대). 자정이 없는 시간대 전환일은 그날 첫 시각이다.
  /// 기기 달력이 그레고리력이 아니어도 날짜는 서기로 센다(`LocalDate` 원칙).
  public static func startOfDay(_ date: LocalDate, calendar: Calendar) -> Date? {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    return date.noon(in: calendar).map { gregorian.startOfDay(for: $0) }
  }
}
