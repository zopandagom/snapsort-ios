import Foundation

/// 캡처 인박스 기간: 오늘을 포함한 최근 30일(기기 달력·시간대) (docs/ARCHITECTURE.md §4 정리 도우미).
public enum CaptureInboxWindow {
  public static let days = 30

  /// 오늘 0시에서 29일 전 날의 0시(`calendar.startOfDay`). 이 시각 이상에 생성된 스크린샷이 대상이다.
  /// 시간대 전환일에 0시가 없어도 `startOfDay` 가 그날의 첫 시각을 준다.
  /// 계산하지 못하면 nil(부르는 쪽은 빈 인박스로 본다).
  public static func start(now: Date, calendar: Calendar) -> Date? {
    guard let day = calendar.date(byAdding: .day, value: -(self.days - 1), to: calendar.startOfDay(for: now)) else {
      return nil
    }
    return calendar.startOfDay(for: day)
  }
}
