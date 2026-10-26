import Core
import Foundation
import WidgetKit

/// 만료 임박 위젯이 한 시각부터 보일 값. 개수와 날짜만 담는다(교환처·식별자 없음, docs/CONVENTIONS.md §4).
public struct ExpiryWidgetEntry: TimelineEntry, Sendable, Hashable {
  public enum Content: Sendable, Hashable {
    /// 저장소를 열거나 읽지 못했다("앱을 열어 주세요").
    case unavailable
    case summary(ExpiryWidgetSummary)
  }

  public let date: Date
  public let content: Content

  public init(date: Date, content: Content) {
    self.date = date
    self.content = content
  }

  /// 위젯 갤러리와 자리 표시용 예시 값(2개, D-3). 실제 저장소 값이 아니다.
  static func example(date: Date, calendar: Calendar) -> ExpiryWidgetEntry {
    ExpiryWidgetEntry(
      date: date,
      content: .summary(ExpiryWidgetSummary(
        date: LocalDate(date, calendar: calendar),
        count: 2,
        nearestDaysLeft: 3,
        isChecking: false
      ))
    )
  }
}
