import Core
import Foundation
import PhotoStoreInterface
import WidgetKit

/// 만료 임박 위젯의 타임라인 (docs/ARCHITECTURE.md §4 만료 임박 위젯).
/// `@Observable` Model 대신 WidgetKit 의 Provider 다: 상태를 entry 값으로 넘기고 View 는 그 값만 그린다(이벤트 메서드 없음).
/// 타임라인을 만들 때마다 저장소를 새로 열어, 앱이 저장소를 옮기거나 경량 이전을 한 뒤에도 새 파일을 읽는다.
/// 저장소에는 읽기 두 개(추출 대기·만료 예정)만 부른다.
public struct ExpiryWidgetProvider: TimelineProvider, Sendable {
  /// 저장소를 열지 못했을 때 다시 읽기를 요청하는 간격. 위젯만 잠깐 실패했는데 앱이 다시 요청하지 않는 경우에 하루 동안 굳지 않게 한다.
  static let unavailableRetryInterval: TimeInterval = 30 * 60

  private let makeStore: @Sendable () -> (any PhotoStoreClient)?
  private let calendar: Calendar
  private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - makeStore: 읽기 전용 저장소를 연다. 열 수 없으면(group 컨테이너 없음·저장 파일 없음·열기 실패) nil.
  ///   - calendar: 오늘과 날의 시작을 정하는 기기 달력. 시간대만 쓰고 날짜는 그레고리력으로 센다.
  ///   - now: 지금 시각. 타임라인마다 한 번 읽는다.
  public init(
    makeStore: @escaping @Sendable () -> (any PhotoStoreClient)?,
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.makeStore = makeStore
    self.calendar = calendar
    self.now = now
  }

  public func placeholder(in _: Context) -> ExpiryWidgetEntry {
    .example(date: self.now(), calendar: self.calendar)
  }

  /// 위젯 갤러리에서는 예시 값을, 그 밖에는 지금 타임라인의 첫 entry 를 보인다.
  public func getSnapshot(in context: Context, completion: @escaping @Sendable (ExpiryWidgetEntry) -> Void) {
    guard !context.isPreview else {
      completion(.example(date: self.now(), calendar: self.calendar))
      return
    }
    Task {
      let timeline = await self.timeline()
      completion(timeline.entries.first ?? ExpiryWidgetEntry(date: self.now(), content: .unavailable))
    }
  }

  /// WidgetKit 은 completion 을 기다릴 뿐 취소하지 않는다. 겹쳐 불려도 호출마다 자기 저장소를 열고 읽기만 한다.
  public func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<ExpiryWidgetEntry>) -> Void) {
    Task {
      await completion(self.timeline())
    }
  }

  /// 정상이면 오늘(지금부터)과 그 뒤 7일(각 날의 시작부터) entry 8개를 넣고 내일 시작에 다시 읽는다.
  /// 시스템이 다시 읽기를 미뤄도 미리 넣은 entry 가 날짜 경계에서 맞는 값을 보인다.
  /// 저장소를 열거나 읽지 못하면 `.unavailable` 하나를 넣고 30분 뒤(내일 시작이 더 이르면 그때) 다시 읽는다.
  func timeline() async -> Timeline<ExpiryWidgetEntry> {
    let now = self.now()
    let today = LocalDate(now, calendar: self.calendar)
    let tomorrowStart = ExpiryWidgetTimeline.startOfDay(today.addingDays(1), calendar: self.calendar)
    guard let summaries = await self.summaries(today: today) else {
      let retry = now.addingTimeInterval(Self.unavailableRetryInterval)
      return Timeline(
        entries: [ExpiryWidgetEntry(date: now, content: .unavailable)],
        policy: .after(tomorrowStart.map { min(retry, $0) } ?? retry)
      )
    }
    let entries = summaries.enumerated().compactMap { offset, summary -> ExpiryWidgetEntry? in
      let date = offset == 0 ? now : ExpiryWidgetTimeline.startOfDay(summary.date, calendar: self.calendar)
      return date.map { ExpiryWidgetEntry(date: $0, content: .summary(summary)) }
    }
    return Timeline(entries: entries, policy: tomorrowStart.map { .after($0) } ?? .atEnd)
  }

  /// 추출 대기를 먼저 읽는다(만료 알림 동기화와 같은 순서). 열거나 읽지 못하면 nil.
  private func summaries(today: LocalDate) async -> [ExpiryWidgetSummary]? {
    guard let store = self.makeStore() else { return nil }
    do throws(PhotoStoreError) {
      let pendingExtractionIDs = try await store.gifticonExtractionPendingIDs()
      let expiries = try await store.upcomingGifticonExpiries(from: today)
      return ExpiryWidgetTimeline.summaries(for: expiries, isChecking: !pendingExtractionIDs.isEmpty, today: today)
    } catch {
      return nil
    }
  }
}
