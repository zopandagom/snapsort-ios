import Core
import Foundation
import WidgetTimelineInterface

/// 만료 알림 동기화가 읽은 만료 예정으로 위젯에 보일 요약을 계산해, 지난 요청 때와 다를 때만 위젯 갱신을 요청한다
/// (docs/ARCHITECTURE.md §4 만료 임박 위젯). `LibraryReminderSync` 가 소유한다. 이 파일로 나눈 것은 LibraryModel 파일 길이 때문이다.
@MainActor
final class LibraryWidgetReload {
  /// 마지막으로 위젯 갱신을 요청할 때의 요약. nil 이면 아직 요청하지 않았다. 값이 같으면 다시 요청하지 않는다.
  private var requestedSummaries: [ExpiryWidgetSummary]?

  private let widgetTimeline: (any WidgetTimelineClient)?
  private let calendar: Calendar

  init(widgetTimeline: (any WidgetTimelineClient)?, calendar: Calendar) {
    self.widgetTimeline = widgetTimeline
    self.calendar = calendar
  }

  /// 비교와 요청 사이에 기다리지 않아 겹치지 않는다. 요약에 날짜가 들어 있어 자정을 넘기면(`dayChanged`) 하루 한 번 더 요청한다.
  func expiriesRead(_ expiries: [GifticonExpiry], isChecking: Bool, now: Date) {
    guard let widgetTimeline = self.widgetTimeline else { return }
    let summaries = ExpiryWidgetTimeline.summaries(
      for: expiries,
      isChecking: isChecking,
      today: LocalDate(now, calendar: self.calendar)
    )
    guard summaries != self.requestedSummaries else { return }
    self.requestedSummaries = summaries
    widgetTimeline.reloadExpiryWidget()
  }
}
