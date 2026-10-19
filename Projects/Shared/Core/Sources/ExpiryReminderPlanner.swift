import Foundation

/// 하루에 울릴 만료 알림 하나. 같은 날 울릴 7일 전·1일 전 알림을 묶는다.
public struct ExpiryReminder: Sendable, Hashable {
  /// 알림이 울리는 날(기기 시간대의 09:00, `ExpiryReminderPlanner.reminderHour`).
  public let date: LocalDate
  /// 이 날 기준 내일 만료되는 기프티콘 수(1일 전 알림).
  public let expiringTomorrowCount: Int
  /// 이 날 기준 7일 뒤 만료되는 기프티콘 수(7일 전 알림).
  public let expiringInWeekCount: Int

  public init(date: LocalDate, expiringTomorrowCount: Int, expiringInWeekCount: Int) {
    self.date = date
    self.expiringTomorrowCount = expiringTomorrowCount
    self.expiringInWeekCount = expiringInWeekCount
  }
}

/// 대기 알림을 원하는 알림에 맞추는 데 지울 것과 더할 것.
public struct ReminderChanges: Sendable, Equatable {
  /// 지울 대기 알림 식별자(관리 앞부분 중 원하지 않는 것).
  public let removals: Set<String>
  /// 더할 알림 식별자(원하는데 대기에 없는 것).
  public let additions: Set<String>

  public init(removals: Set<String>, additions: Set<String>) {
    self.removals = removals
    self.additions = additions
  }
}

/// 기프티콘 만료일로 만료 알림을 계획하고 대기 알림과의 차이를 구하는 규칙 (docs/ARCHITECTURE.md §4 만료 알림).
/// 문구와 식별자는 두지 않는다(Core 는 문구를 갖지 않는다). 여러 Client 결과(저장소·알림 권한·대기 알림)를 받아 판단하므로
/// Core 순수 함수로 두어, 다른 Feature 가 같은 동기화를 필요로 하면 조합 Client 로 옮길 수 있게 한다.
public enum ExpiryReminderPlanner {
  public static let reminderHour = 9
  public static let reminderMinute = 0
  /// iOS 가 앱마다 남기는 대기 알림 수 상한. 넘으면 시스템이 가장 늦은 것부터 버린다.
  public static let maximumCount = 64
  /// 7일 전, 1일 전.
  static let daysBefore = [7, 1]

  /// - Parameters:
  ///   - expiries: 같은 `imageID` 가 여러 번 오면 한 번만 센다(마지막 값).
  ///   - now: 지금 시각. 오늘과 지금 시·분을 `calendar` 의 시간대로 정한다.
  ///   - calendar: 앱은 기기 달력(`autoupdatingCurrent`). 시간대만 쓰고 연·월·일은 그레고리력으로 센다(`LocalDate(_:calendar:)` 와 같은 원칙).
  /// - Returns: 날짜 오름차순, 최대 `maximumCount` 개(가까운 날부터). 울릴 시각(그날 09:00)이 `now` 와 같거나 지난 알림은 뺀다.
  public static func reminders(for expiries: [GifticonExpiry], now: Date, calendar: Calendar) -> [ExpiryReminder] {
    let expiryDates = Dictionary(expiries.map { ($0.imageID, $0.expiryDate) }, uniquingKeysWith: { _, last in last })
    let today = LocalDate(now, calendar: calendar)
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let time = gregorian.dateComponents([.hour, .minute], from: now)
    let hasPassedTodayReminder = (time.hour ?? 0, time.minute ?? 0) >= (Self.reminderHour, Self.reminderMinute)

    var counts: [LocalDate: (tomorrow: Int, inWeek: Int)] = [:]
    for expiryDate in expiryDates.values {
      for daysBefore in Self.daysBefore {
        let date = expiryDate.addingDays(-daysBefore)
        guard date > today || (date == today && !hasPassedTodayReminder) else {
          continue
        }
        var count = counts[date, default: (0, 0)]
        if daysBefore == 1 {
          count.tomorrow += 1
        } else {
          count.inWeek += 1
        }
        counts[date] = count
      }
    }
    let reminders = counts
      .map {
        ExpiryReminder(date: $0.key, expiringTomorrowCount: $0.value.tomorrow, expiringInWeekCount: $0.value.inWeek)
      }
      .sorted { $0.date < $1.date }
    return Array(reminders.prefix(Self.maximumCount))
  }

  /// 대기 알림을 원하는 알림에 맞추는 데 지울 것과 더할 것. nil 이면 예약을 건드리지 않는다.
  /// - Parameters:
  ///   - desiredIDs: 원하는 알림 식별자(`managedPrefix` 로 시작한다).
  ///   - pendingIDs: 이 앱의 대기 알림 식별자 전체. `managedPrefix` 로 시작하지 않는 것은 건드리지 않는다.
  ///   - isAuthorized: 알림 권한이 있는지. 없으면(미정·거부) nil: 권한이 없으면 울리지 않고, 다시 허용하면 다음 동기화가 맞춘다.
  ///   - hasPendingExtraction: 추출 대기 이미지가 있는지. 있으면 nil: 그 이미지의 이전 만료일을 몰라, 날짜로 묶은 알림에서
  ///     그 몫만 남길 수 없다(저장소의 nil 은 알림을 지우는 근거가 아니다, ARCHITECTURE §4 저장소).
  public static func changes(
    desiredIDs: Set<String>,
    pendingIDs: Set<String>,
    managedPrefix: String,
    isAuthorized: Bool,
    hasPendingExtraction: Bool
  ) -> ReminderChanges? {
    guard isAuthorized, !hasPendingExtraction else {
      return nil
    }
    let managedPendingIDs = pendingIDs.filter { $0.hasPrefix(managedPrefix) }
    return ReminderChanges(
      removals: managedPendingIDs.subtracting(desiredIDs),
      additions: desiredIDs.subtracting(pendingIDs)
    )
  }
}
