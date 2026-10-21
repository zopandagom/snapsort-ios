import Core
import Foundation
import NotificationInterface
import UIKit
import UserNotifications

/// UserNotifications 기반 구현. 날짜·시각 트리거로 한 번 울리는 로컬 알림만 예약한다 (docs/ARCHITECTURE.md §4 만료 알림).
/// 비 Sendable 인 `UNUserNotificationCenter` 를 들고 있지 않도록 메서드마다 `current()` 를 쓴다.
/// 앱이 앞에 있을 때의 표시는 `registerForegroundPresentation()` 으로 등록한다.
public struct NotificationClientImpl: NotificationClient {
  public init() {}

  /// 앱이 앞에 있을 때도 알림을 보이게 등록한다. App 이 실행 직후(`SnapSortApp.init`) 한 번 부른다. 다시 불러도 같다.
  @MainActor
  public static func registerForegroundPresentation() {
    UNUserNotificationCenter.current().delegate = ForegroundPresenter.shared
  }

  public func authorizationStatus() async -> NotificationAuthorization {
    await Self.authorization(UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
  }

  public func requestAuthorization() async -> NotificationAuthorization {
    // 실패해도 지금 상태를 돌려준다(대개 미정이라 다시 요청할 수 있다).
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    return await self.authorizationStatus()
  }

  public func pendingRequestIDs() async -> Set<String> {
    await Set(UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
  }

  public func add(_ requests: [NotificationRequest]) async throws(NotificationError) {
    let center = UNUserNotificationCenter.current()
    var hasFailure = false
    // 앞 요청의 실패(예: 계산 직후 울릴 시각이 지남)가 나머지를 막지 않게 끝까지 넣는다. 원인 오류는 남기지 않는다.
    for request in requests {
      guard let notificationRequest = Self.request(request, calendar: .autoupdatingCurrent) else {
        hasFailure = true
        continue
      }
      do {
        try await center.add(notificationRequest)
      } catch {
        hasFailure = true
      }
    }
    if hasFailure {
      throw .failed
    }
  }

  public func removePendingRequests(ids: Set<String>) async {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(ids))
  }

  public func openSettings() async {
    guard let url = Self.settingsURL else {
      return
    }
    await Self.open(url)
  }

  /// 설정 앱의 이 앱 알림 설정(`app-settings:notifications`).
  static var settingsURL: URL? {
    URL(string: UIApplication.openNotificationSettingsURLString)
  }

  @MainActor
  private static func open(_ url: URL) async {
    _ = await UIApplication.shared.open(url)
  }

  /// 모르는 상태에선 예약하지 않도록 거부로 본다.
  static func authorization(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
    switch status {
    case .notDetermined:
      .notDetermined
    case .denied:
      .denied
    case .authorized, .provisional, .ephemeral:
      .authorized
    @unknown default:
      .denied
    }
  }

  /// 그레고리력 날짜·시각을 `calendar`(앱은 `Calendar.autoupdatingCurrent`)의 구성 요소로 바꾼다.
  /// calendar·timeZone 은 비워 둔다: 트리거가 울릴 때의 기기 달력·시간대로 맞춰 시간대를 바꿔도 그곳의 09:00 에 울린다.
  /// 그레고리력 연도를 그대로 넣으면 기기 달력이 일본력·불교력일 때 다른 해로 읽혀 울리지 않으므로 기기 달력의 era·연도로 바꾼다
  /// (중국력 등의 윤달은 `dateComponents(_:from:)` 가 `isLeapMonth` 를 함께 채운다).
  static func triggerDateComponents(for request: NotificationRequest, calendar: Calendar) -> DateComponents? {
    var components = request.date.dateComponents
    components.hour = request.hour
    components.minute = request.minute
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    guard let date = gregorian.date(from: components) else {
      return nil
    }
    return calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: date)
  }

  static func request(_ request: NotificationRequest, calendar: Calendar) -> UNNotificationRequest? {
    guard let components = triggerDateComponents(for: request, calendar: calendar) else {
      return nil
    }
    let content = UNMutableNotificationContent()
    content.title = request.title
    content.body = request.body
    content.sound = .default
    return UNNotificationRequest(
      identifier: request.id,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    )
  }
}
