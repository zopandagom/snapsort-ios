import Foundation

/// 여행의 표시 날짜와 그 기간 캡처 조회 범위 (docs/ARCHITECTURE.md §4 여행 폴더).
/// 기간은 여행지 시각으로 첫 사진 날 0시부터 마지막 사진 다음 날 0시 전까지다. 사진에는 시간대가 없어(PhotoKit) 여행지 시간대를
/// 알 때(지오코딩 응답을 캐시함)만 그대로 계산하고, 모르면 대체 규칙으로 여행지 날짜를 놓치지 않게 범위를 넓힌다.
/// - 알려진 한계 (a): 시간대를 모르면 기기 시간대·경도 추정이 실제와 다른 곳에서 첫·마지막 사진이 여행지 자정에서 그 차이 안이면
///   표시 날짜가 하루 밀린다(캡처는 넓힌 범위라 빠지지 않는다). 상세를 온라인으로 한 번 열어 시간대가 캐시되면 고쳐진다.
/// - 알려진 한계 (b): 시간대를 알아도 중심점의 시간대 하나로 계산하므로, 다른 시간대에서 찍은 첫·마지막 사진이 여행지 자정에서
///   두 시간대 차이 안이면 그날이 하루 밀려 표시 날짜가 바뀌고 그날 캡처가 빠진다(반대쪽이면 섞인다).
public struct TripPeriod: Sendable, Hashable {
  /// 날짜를 나눈 시간대. 캐시된 여행지 시간대, 기기 시간대 또는 경도로 추정한 고정 오프셋.
  public let timeZone: TimeZone
  /// 실제 시간대(지오코딩 응답)로 계산했는지. false 면 대체 규칙이라 표시 날짜가 어긋날 수 있다.
  public let isTimeZoneKnown: Bool
  /// 첫·마지막 사진의 그 시간대 날짜(그레고리력).
  public let firstDay: LocalDate
  public let lastDay: LocalDate
  /// 캡처 조회 범위(끝 제외). 시간대를 알면 [firstDay 0시, lastDay 다음 날 0시), 모르면 대체 규칙으로 넓힌 범위.
  public let captureInterval: DateInterval

  /// 대체 규칙에서 기기 시간대를 쓸 때의 오차 한도. 추정이 기기와 1시간 이하로 달라도 실제는 2시간 다를 수 있다
  /// (서울 기기: 시드니·멜버른·호바트 일광절약 중 +11, 애들레이드 +10.5, 마가단·사할린 +11).
  /// 시드니 1월·마가단은 실제 차가 이 값과 딱 같아, 서울 기기에서 첫 사진이 10:00 이면 범위가 여행지 첫날 00:00 정각에서 시작한다.
  /// 줄이면 그날 자정 직후 캡처가 빠진다(`TripPeriodTests` 가 이 경계를 고정한다).
  static let deviceTimeZoneUncertainty: TimeInterval = 2 * 3600
  /// 대체 규칙에서 경도 추정 고정 오프셋의 오차 한도(대부분 2시간 이하 + 일광절약 1시간).
  static let estimatedTimeZoneUncertainty: TimeInterval = 3 * 3600
  /// 경도 추정이 기기 오프셋과 이만큼 이하로 다르면 기기 시간대를 쓴다(국내·같은 시간대 여행은 날짜가 정확하고 일광절약도 따른다).
  static let deviceTimeZoneTolerance = 3600

  /// - Parameters:
  ///   - calendar: 기기 달력(시간대만 쓴다. 하루 경계는 달력 체계와 무관하다).
  ///   - knownTimeZone: 캐시된 여행지 시간대. 있으면 그 시간대로, 여유 없이 확정 정의대로 계산한다.
  ///     없으면 대체 규칙: 경도/15 추정이 기기 오프셋과 1시간 이하로 다르면 기기 시간대·여유 `deviceTimeZoneUncertainty`,
  ///     아니면 추정 고정 오프셋·여유 `estimatedTimeZoneUncertainty`. 범위는 [dayStart(첫 사진 − 여유) − 여유,
  ///     dayEnd(마지막 사진 + 여유) + 여유) 로, 실제 오프셋이 그 시간대 ± 여유 안이면 여행지 기간을 늘 포함한다.
  public init(trip: Trip, calendar: Calendar, knownTimeZone: TimeZone?) {
    let (timeZone, margin) = knownTimeZone.map { ($0, 0) } ?? Self.fallback(
      trip: trip,
      deviceTimeZone: calendar.timeZone
    )
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = timeZone
    let start = trip.startDate
    // `DateInterval(start:end:)` 는 end < start 면 멈추므로 마지막 시각을 첫 시각 이상으로 둔다.
    let end = max(trip.endDate, start)
    // 하루의 끝은 `startOfDay + 1일` 이 아니라 `dateInterval(of: .day)` 로 구한다. 자정이 없는 날(일광절약 시작)에는
    // 하루가 01:00 에 시작해 `+1일` 이 다음 날 01:00 이 된다.
    let dayStart = gregorian.dateInterval(of: .day, for: start - margin)?.start ?? start - 86400
    let dayEnd = gregorian.dateInterval(of: .day, for: end + margin)?.end ?? end + 86400
    self.timeZone = timeZone
    self.isTimeZoneKnown = knownTimeZone != nil
    self.firstDay = LocalDate(start, calendar: gregorian)
    self.lastDay = LocalDate(trip.endDate, calendar: gregorian)
    self.captureInterval = DateInterval(start: dayStart - margin, end: dayEnd + margin)
  }

  /// 시간대를 모를 때 쓸 시간대와 여유.
  private static func fallback(trip: Trip, deviceTimeZone: TimeZone) -> (TimeZone, TimeInterval) {
    let longitude = trip.center.longitude
    guard longitude.isFinite else {
      return (deviceTimeZone, self.deviceTimeZoneUncertainty)
    }
    let estimate = min(max(Int((longitude / 15).rounded(.toNearestOrAwayFromZero)), -12), 14)
    let device = deviceTimeZone.secondsFromGMT(for: trip.startDate)
    if abs(device - estimate * 3600) <= self.deviceTimeZoneTolerance {
      return (deviceTimeZone, self.deviceTimeZoneUncertainty)
    }
    guard let estimated = TimeZone(secondsFromGMT: estimate * 3600) else {
      return (deviceTimeZone, self.deviceTimeZoneUncertainty)
    }
    return (estimated, self.estimatedTimeZoneUncertainty)
  }
}
