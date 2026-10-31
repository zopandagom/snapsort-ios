import Core
import Foundation
import NotificationInterface
import Observation
import PhotoStoreInterface
import WidgetTimelineInterface

/// 보관함 화면의 만료 알림 동기화 (docs/ARCHITECTURE.md §4 만료 알림). `LibraryModel` 이 소유하고 계기(인덱싱 진행률, 앱 복귀,
/// 기프티콘 사용 여부·날짜 변경, 권한 요청)를 넘긴다. 이 파일로 나눈 것은 LibraryModel 파일 길이 때문이다.
/// 세 상태(`authorization`·`hasPlannedReminder`·`isRequestingAuthorization`)의 문서 주석은 여기에 있고, LibraryModel 의 같은 뜻
/// public 계산 프로퍼티(`notificationAuthorization`·`hasPlannedReminder`·`isRequestingNotificationAuthorization`)는 이 값을 가리킨다.
/// 동기화 요청은 하나씩 차례로 처리해 동기화가 겹치지 않게 한다. 도는 중 들어온 요청 여러 개는 끝난 뒤 한 번으로 합친다
/// (요청은 "지금 상태로 다시 맞춰라"라서 합쳐도 된다). 알림이나 저장소가 없으면 시작하지 않는다.
@MainActor
@Observable
final class LibraryReminderSync {
  /// 알림 권한. 아직 읽지 않았거나 알림·저장소가 없으면 nil.
  private(set) var authorization: NotificationAuthorization?
  /// 지금 예약할 만료 알림이 하나 이상인지(같은 `now` 로 계산한 planner 결과가 비어 있지 않음). 권한과 관계없이 계산한다.
  /// 오늘·내일(09:00 뒤) 만료처럼 알림이 하나도 안 나오는 기프티콘만 있으면 거짓이라, 허용해도 예약이 0 개인 버튼을 보이지 않는다.
  /// 마지막으로 저장소를 읽은 결과이고, 읽지 못하면 지난 값을 둔다.
  private(set) var hasPlannedReminder = false
  /// 권한 팝업이 떠 있는 동안 참. 버튼을 숨겨 두 번 요청하지 않게 한다.
  private(set) var isRequestingAuthorization = false

  /// 만료 알림을 지금 상태로 다시 맞추라는 신호. `run()` 이 구독하는 동안만 의미가 있다.
  @ObservationIgnored private var requests: AsyncStream<Void>.Continuation?
  /// `run()` 을 시작할 때마다 하나씩 올린다. 화면을 나갔다 바로 들어와 지난 동기화가 늦게 깨어나도 상태와 예약을 바꾸지 않게 한다.
  @ObservationIgnored private var generation = 0
  /// 권한 요청을 시작할 때마다 하나씩 올린다. 요청과 겹친 동기화가 요청 전에 읽은 권한으로 상태를 덮지 않게 한다.
  @ObservationIgnored private var authorizationRequestCount = 0

  @ObservationIgnored private let notification: (any NotificationClient)?
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let widgetReload: LibraryWidgetReload
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private let now: @Sendable () -> Date

  /// 매개변수 뜻은 `LibraryModel.init` 과 같다.
  init(
    notification: (any NotificationClient)?,
    photoStore: (any PhotoStoreClient)?,
    widgetTimeline: (any WidgetTimelineClient)?,
    calendar: Calendar,
    now: @escaping @Sendable () -> Date
  ) {
    self.notification = notification
    self.photoStore = photoStore
    self.widgetReload = LibraryWidgetReload(widgetTimeline: widgetTimeline, calendar: calendar)
    self.calendar = calendar
    self.now = now
  }

  /// 화면 진입 동기화를 하고 요청을 기다린다. 부른 Task 가 취소되면(화면이 사라짐) 끝난다.
  func run() async {
    guard let notification = self.notification, let photoStore = self.photoStore else { return }
    self.generation += 1
    let generation = self.generation
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.requests = continuation
    // 화면 진입 동기화.
    continuation.yield()
    for await _ in requests {
      guard self.isCurrent(generation) else { return }
      await self.sync(notification: notification, photoStore: photoStore, generation: generation)
    }
  }

  /// 화면을 떠나 동기화 루프가 끝났으면 신호는 버려지고, 다음 화면 진입이 동기화한다.
  func request() {
    self.requests?.yield()
  }

  /// 알림 권한을 요청하고 동기화를 요청한다. 권한을 정하지 않았고 팝업이 떠 있지 않을 때만.
  func requestAuthorization() async {
    guard let notification = self.notification, self.authorization == .notDetermined,
          !self.isRequestingAuthorization
    else { return }
    self.isRequestingAuthorization = true
    self.authorizationRequestCount += 1
    let status = await notification.requestAuthorization()
    self.isRequestingAuthorization = false
    self.authorization = status
    self.request()
  }

  /// 설정 앱의 이 앱 알림 설정을 연다. 알림을 거부했을 때만.
  func openSettings() async {
    guard let notification = self.notification, self.authorization == .denied else { return }
    await notification.openSettings()
  }

  /// 권한을 읽고, 저장소의 만료 예정으로 원하는 알림을 계산해 대기 알림과의 식별자 차이만 지우고 더한다.
  /// 저장소를 읽지 못하거나 추출 대기가 있으면 예약을 바꾸지 않는다(판단은 `ExpiryReminderPlanner.changes`,
  /// docs/ARCHITECTURE.md §4 만료 알림). 기다린 뒤에는 늘 지금 번호인지 확인해, 지난 루프가 상태와 예약을 바꾸지 않게 한다.
  /// 같은 읽기로 위젯에 보일 요약을 계산해, 지난 요청 때와 다를 때만 위젯 갱신을 요청한다(알림 권한과 관계없이,
  /// docs/ARCHITECTURE.md §4 만료 임박 위젯). 저장소를 읽지 못하면 요청하지 않는다.
  private func sync(
    notification: any NotificationClient,
    photoStore: any PhotoStoreClient,
    generation: Int
  ) async {
    // 권한 요청과 겹쳐 요청 전에 읽은 값이거나 팝업 중에 읽은 값(미정)이면 상태를 덮지 않는다.
    // 아래 판단도 이번에 읽은 값으로 해, 지난 값이면 예약하지 않고 요청이 끝난 뒤의 동기화에 맡긴다.
    let requestCount = self.authorizationRequestCount
    let wasRequesting = self.isRequestingAuthorization
    let status = await notification.authorizationStatus()
    guard self.isCurrent(generation) else { return }
    if requestCount == self.authorizationRequestCount, !wasRequesting, !self.isRequestingAuthorization {
      self.authorization = status
    }

    let now = self.now()
    let pendingExtractionIDs: Set<ImageAsset.ID>
    let expiries: [GifticonExpiry]
    do throws(PhotoStoreError) {
      // 추출 대기를 먼저 읽는다. 한 실행 안에서 추출 대기는 줄기만 하므로, 비었다고 읽은 뒤에는 만료 예정에서 빠질 이미지가 생기지 않는다.
      pendingExtractionIDs = try await photoStore.gifticonExtractionPendingIDs()
      expiries = try await photoStore.upcomingGifticonExpiries(from: LocalDate(now, calendar: self.calendar))
    } catch {
      return
    }
    guard self.isCurrent(generation) else { return }
    self.widgetReload.expiriesRead(expiries, isChecking: !pendingExtractionIDs.isEmpty, now: now)
    let desired = ExpiryReminderPlanner.reminders(for: expiries, now: now, calendar: self.calendar)
      .map { $0.notificationRequest(calendar: self.calendar) }
    self.hasPlannedReminder = !desired.isEmpty

    await Self.applyReminderChanges(
      desired, status: status, hasPendingExtraction: !pendingExtractionIDs.isEmpty, notification: notification
    ) { self.isCurrent(generation) }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }

  /// 원하는 알림과 대기 알림의 식별자 차이만 지우고 더한다(판단은 `ExpiryReminderPlanner.changes`, docs/ARCHITECTURE.md §4 만료 알림).
  /// 대기 알림을 읽은 뒤 `isCurrent` 가 거짓이면(지난 동기화 루프) 예약을 바꾸지 않는다.
  static func applyReminderChanges(
    _ desired: [NotificationRequest],
    status: NotificationAuthorization,
    hasPendingExtraction: Bool,
    notification: any NotificationClient,
    isCurrent: () -> Bool
  ) async {
    // `changes` 가 nil 을 낼 조건이면 알림 센터를 부르지 않는다.
    guard status == .authorized, !hasPendingExtraction, !Task.isCancelled else { return }
    let pendingIDs = await notification.pendingRequestIDs()
    guard isCurrent(), !Task.isCancelled,
          let changes = ExpiryReminderPlanner.changes(
            desiredIDs: Set(desired.map(\.id)),
            pendingIDs: pendingIDs,
            managedPrefix: ExpiryReminder.notificationIDPrefix,
            isAuthorized: status == .authorized,
            hasPendingExtraction: hasPendingExtraction
          )
    else { return }
    // 지우기와 더하기는 같은 시점의 계산이라 사이에 멈추지 않는다. 지우기를 먼저 해 대기 상한을 넘지 않게 한다.
    if !changes.removals.isEmpty {
      await notification.removePendingRequests(ids: changes.removals)
    }
    let additions = desired.filter { changes.additions.contains($0.id) }
    if !additions.isEmpty {
      // 실패한 것만 빠지고 나머지는 예약된다. 빠진 것은 다음 동기화가 다시 더한다.
      try? await notification.add(additions)
    }
  }
}
