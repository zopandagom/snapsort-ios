import Core
import Foundation
import IndexingInterface
import NotificationInterface
import Observation
import PhotoLibraryInterface
import PhotoStoreInterface
import WidgetTimelineInterface

/// 이미지 보관함 화면의 상태와 로직.
/// 상태는 모두 private(set) 이고, View 는 이벤트 메서드 호출로만 상태 변경을 요청한다.
/// 권한 분기는 App 과 OnboardingFeature 가 맡으므로, 이 화면은 읽을 수 있는 권한이 있을 때만 뜬다.
@MainActor
@Observable
public final class LibraryModel {
  public private(set) var imageCount = 0
  /// 사용자가 고른 사진만 읽을 수 있는 제한 접근 상태인지. 화면에 안내 배너를 띄우는 데 쓴다.
  public private(set) var isLimited: Bool
  /// 분류 인덱싱 진행률. 인덱싱을 시작하기 전이나 인덱서가 없으면 nil.
  /// 인덱싱이 멈춰도 마지막 값을 남겨 어디까지 분석했는지 보여 준다. 화면은 `phase` 로 분류 중(1단계)·글자 읽는 중(2단계)을 나눠 보인다.
  public private(set) var indexingProgress: IndexingProgress?
  /// 인덱싱이 중간에 멈췄는지 (저장소를 읽거나 쓰지 못함 등). 화면에 다시 시도 안내를 띄운다.
  /// 인덱서는 보관함 변경을 계속 관찰하므로 정상이면 스트림이 끝나지 않는다. 그래서 스트림이 끝나면 멈춘 것으로 본다.
  public private(set) var isIndexingStopped = false
  /// 분석할 이미지가 남아 인덱싱이 돌고 있는지. 분류를 마친 뒤 OCR 대기 이미지의 글자를 읽는 동안(2단계)도 참이다.
  /// 첫 진행률을 받기 전(보관함과 저장소 비교 중)에도 참이다. 두 단계를 다 마쳤거나, 멈췄거나, 화면이 사라져 구독을 끝내면 거짓이다.
  public private(set) var isIndexing = false
  /// 카테고리별 개수. 이미지가 없는 카테고리는 빠진다.
  /// `.travel` 은 여행 사진 수가 아니라 여행 판정으로 찾은 여행 수다.
  public private(set) var categoryCounts: [ImageCategory: Int] = [:]
  /// 알림 권한. 아직 읽지 않았거나 알림·저장소가 없으면 nil.
  public private(set) var notificationAuthorization: NotificationAuthorization?
  /// 지금 예약할 만료 알림이 하나 이상인지(같은 `now` 로 계산한 planner 결과가 비어 있지 않음). 권한과 관계없이 계산한다.
  /// 오늘·내일(09:00 뒤) 만료처럼 알림이 하나도 안 나오는 기프티콘만 있으면 거짓이라, 허용해도 예약이 0 개인 버튼을 보이지 않는다.
  /// 마지막으로 저장소를 읽은 결과이고, 읽지 못하면 지난 값을 둔다.
  public private(set) var hasPlannedReminder = false
  /// 권한 팝업이 떠 있는 동안 참. 버튼을 숨겨 두 번 요청하지 않게 한다.
  public private(set) var isRequestingNotificationAuthorization = false
  /// 저장소 내용이 바뀌었을 수 있다고 알게 될 때마다 하나씩 오른다: 인덱싱 진행률을 받을 때(소급이 끝날 때 오는 같은 값 진행률 포함)와
  /// 인덱싱이 멈출 때. 카테고리 화면·기프티콘 목록·영수증 목록·상세의 기프티콘 정보·여행 폴더 목록·여행 폴더 상세·검색 결과·정리 화면·캡처 인박스가
  /// 이 변화로 다시 읽는다(LibraryView 가 CategoryModel·GifticonListModel·ReceiptListModel·CaptureActionsModel·TripListModel·
  /// TripDetailModel·SearchModel·CleanupModel·CaptureInboxModel 에 넘긴다).
  /// 같은 값 진행률도 놓치지 않도록 진행률 값이 아니라 번호로 알린다.
  public private(set) var storeRevision = 0

  /// "만료 알림 받기" 버튼을 보일지.
  public var showsExpiryReminderButton: Bool {
    self.notificationAuthorization == .notDetermined && self.hasPlannedReminder
      && !self.isRequestingNotificationAuthorization
  }

  /// "설정에서 알림 켜기"를 보일지: 알림을 거부했고 지금 예약할 알림이 있다.
  public var showsNotificationSettingsButton: Bool {
    self.notificationAuthorization == .denied && self.hasPlannedReminder
  }

  /// 개수가 아니라 식별자 집합으로 들고 있어, 처음 조회 결과와 겹치는 변경이 와도 두 번 세지 않는다.
  @ObservationIgnored private var imageIDs: Set<ImageAsset.ID> = [] {
    didSet { self.imageCount = self.imageIDs.count }
  }

  /// 멈춘 인덱싱을 다시 시작하라는 신호. `runIndexing()` 이 구독하는 동안만 의미가 있다.
  @ObservationIgnored private var indexingRetries: AsyncStream<Void>.Continuation?
  /// `runIndexing()` 을 시작할 때마다 하나씩 올린다. 화면을 나갔다 바로 들어오면 취소된 지난 Task 가
  /// 늦게 깨어날 수 있으므로, 인덱싱 상태는 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var indexingGeneration = 0
  /// 만료 알림을 지금 상태로 다시 맞추라는 신호. `runReminderSync()` 가 구독하는 동안만 의미가 있다.
  @ObservationIgnored private var reminderSyncRequests: AsyncStream<Void>.Continuation?
  /// `runReminderSync()` 를 시작할 때마다 하나씩 올린다. 화면을 나갔다 바로 들어와 지난 동기화가 늦게 깨어나도 상태와 예약을 바꾸지 않게 한다.
  @ObservationIgnored private var reminderGeneration = 0
  /// 권한 요청을 시작할 때마다 하나씩 올린다. 요청과 겹친 동기화가 요청 전에 읽은 권한으로 상태를 덮지 않게 한다.
  @ObservationIgnored private var authorizationRequestCount = 0
  /// 이 Model 이 마지막으로 위젯 갱신을 요청할 때의 요약. nil 이면 아직 요청하지 않았다. 값이 같으면 다시 요청하지 않는다.
  @ObservationIgnored private var requestedWidgetSummaries: [ExpiryWidgetSummary]?

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient
  @ObservationIgnored private let indexing: (any IndexingClient)?
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let notification: (any NotificationClient)?
  @ObservationIgnored private let widgetTimeline: (any WidgetTimelineClient)?
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private let now: @Sendable () -> Date

  /// 권한 상태는 동기로 읽을 수 있으므로 init 에서 읽어 첫 프레임부터 배너가 보이게 한다.
  /// App 은 온보딩 전에 이 Model 을 만들므로, 화면 진입 때도 다시 읽는다.
  /// - Parameters:
  ///   - photoLibrary: 사진 보관함. 권한 상태·이미지 목록과 변경을 읽고, 제한 접근이면 사진 선택 화면을 띄운다.
  ///   - indexing: 분류 인덱서.
  ///   - photoStore: 인덱서가 저장한 분류 결과를 읽는 저장소.
  ///   저장소를 열지 못하면(디스크 공간 부족 등) App 이 둘 다 nil 을 넘기고, 분류 없이 보관함만 보여 준다.
  ///   - notification: 만료 알림. 저장소가 없거나 이것이 nil 이면 알림을 예약하지 않고 버튼도 보이지 않는다.
  ///   - widgetTimeline: 만료 임박 위젯 갱신 요청. 만료 알림 동기화가 위젯에 보일 값이 바뀐 것을 볼 때만 요청한다.
  ///   알림이나 저장소가 없으면 동기화가 돌지 않으므로 위젯 갱신도 하지 않는다.
  ///   - calendar: 알림 날짜·시각과 식별자의 달력 체계를 정하는 기기 달력. 알림 Impl 이 트리거에 쓰는 달력과 같아야 한다.
  ///   - now: 지금 시각. 동기화마다 한 번 읽는다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    indexing: (any IndexingClient)?,
    photoStore: (any PhotoStoreClient)?,
    notification: (any NotificationClient)?,
    widgetTimeline: (any WidgetTimelineClient)?,
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.photoLibrary = photoLibrary
    self.indexing = indexing
    self.photoStore = photoStore
    self.notification = notification
    self.widgetTimeline = widgetTimeline
    self.calendar = calendar
    self.now = now
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  /// 이미지 수 관찰, 분류 인덱싱, 만료 알림 동기화를 함께 시작한다.
  /// View 의 `.task` 수명 동안 이어지고, 화면이 사라져 Task 가 취소되면 모두 끝난다.
  public func onAppear() async {
    await withDiscardingTaskGroup { group in
      group.addTask { await self.observeImages() }
      group.addTask { await self.runIndexing() }
      group.addTask { await self.runReminderSync() }
    }
  }

  /// 고른 사진이 바뀌면 보관함 변경 알림이 오므로 여기서 따로 다시 불러오지 않는다.
  public func selectMorePhotosTapped() async {
    await self.photoLibrary.presentLimitedLibraryPicker()
  }

  /// 멈춘 인덱싱을 다시 시작한다. 인덱서가 저장된 데까지 건너뛰므로 처음부터 분석하지 않는다.
  /// 다시 시작한 인덱싱도 `onAppear()` 의 Task 에서 돌아, 화면이 사라지면 함께 끝난다.
  public func retryIndexingTapped() {
    guard self.isIndexingStopped else { return }
    // 다시 시작하기 전에 또 눌러 신호가 남으면, 다음에 멈췄을 때 누르지 않아도 다시 시작하므로 바로 푼다.
    self.isIndexingStopped = false
    // 다시 시작할 때까지 비는 사이에 "분류된 이미지가 없습니다"가 보이지 않게 바로 켠다.
    self.isIndexing = true
    self.indexingRetries?.yield()
  }

  /// 알림 권한을 요청하고, 허용하면 만료 알림을 예약한다. 버튼은 권한을 정하지 않았을 때만 보인다.
  public func notificationsTapped() async {
    guard let notification = self.notification, self.notificationAuthorization == .notDetermined,
          !self.isRequestingNotificationAuthorization
    else { return }
    self.isRequestingNotificationAuthorization = true
    self.authorizationRequestCount += 1
    let status = await notification.requestAuthorization()
    self.isRequestingNotificationAuthorization = false
    self.notificationAuthorization = status
    // 화면을 떠나 동기화 루프가 끝났으면 신호는 버려지고, 다음 화면 진입이 동기화한다.
    self.requestReminderSync()
  }

  /// 설정 앱의 이 앱 알림 설정을 연다. 알림을 거부했을 때만. 설정에서 허용하고 돌아오면 `sceneBecameActive()` 의 동기화가 예약한다.
  public func notificationSettingsTapped() async {
    guard let notification = self.notification, self.notificationAuthorization == .denied else { return }
    await notification.openSettings()
  }

  /// 앱이 앞으로 돌아왔다(scenePhase `.active`). 설정에서 알림 권한을 바꿨거나 그사이 날짜가 바뀌었을 수 있어 만료 알림을 다시 맞춘다.
  /// 화면을 떠나 동기화 루프가 끝났으면 신호는 버려지고, 다음 화면 진입이 동기화한다(아래 두 이벤트도 같다).
  public func sceneBecameActive() {
    self.requestReminderSync()
  }

  /// 기프티콘 사용 여부가 바뀌었다. 사용한 기프티콘은 알리지 않으므로 만료 알림을 다시 맞춘다.
  public func gifticonUsageChanged() {
    self.requestReminderSync()
  }

  /// 날짜나 시간대가 바뀌었다(앱이 앞에 있는 동안 자정을 넘김 등). 오늘이 바뀌면 원하는 알림·`hasPlannedReminder` 가 바뀌므로 다시 맞춘다.
  public func dayChanged() {
    self.requestReminderSync()
  }

  // MARK: - Private

  /// 보관함 변경 구독을 먼저 시작하고 처음 불러온다. 그래야 처음 불러오는 동안 생긴 변경도 놓치지 않는다.
  /// 이후에는 바뀐 이미지만 반영하고, 무엇이 바뀌었는지 모를 때만 전체를 다시 불러온다.
  private func observeImages() async {
    let changes = await self.photoLibrary.imageChanges()
    await self.reloadImages()
    for await change in changes {
      switch change {
      case let .incremental(inserted, removed):
        self.refreshLimitedAccess()
        self.imageIDs.subtract(removed)
        self.imageIDs.formUnion(inserted.map(\.id))
      case .reloadAll:
        await self.reloadImages()
      }
    }
  }

  /// 지난 결과로 개수를 먼저 보여 준 뒤 인덱싱을 시작한다. 멈추면 다시 시도 신호를 기다린다.
  /// 개수 조회는 이 Task 안에서만 차례로 해서, 늦게 끝난 옛 조회가 새 개수를 덮지 않는다.
  private func runIndexing() async {
    self.indexingGeneration += 1
    let generation = self.indexingGeneration
    // 멈춘 채 화면을 나갔다 들어오면 지난 멈춤이 남아 있다. 개수를 읽는 동안 지난 다시 시도 안내가 보이지 않게 먼저 푼다.
    if self.indexing != nil {
      self.isIndexingStopped = false
      self.isIndexing = true
    }
    await self.refreshCategoryCounts(generation: generation)
    guard self.isCurrent(generation), !Task.isCancelled, let indexing = self.indexing else { return }
    let (retries, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.indexingRetries = continuation
    await self.index(with: indexing, generation: generation)
    for await _ in retries {
      await self.index(with: indexing, generation: generation)
    }
  }

  /// 인덱서는 보관함 변경을 스스로 관찰하므로, 진행률만 받아 상태에 반영한다.
  /// 인덱서는 저장·삭제·여행 교체 뒤와 소급 추출·소급 보강이 끝날 때 진행률을 보내므로, 그때마다 저장소 변경 번호(`storeRevision`)를 올리고
  /// 개수를 다시 읽고 만료 알림 동기화를 요청한다.
  /// 기다린 뒤에는 늘 지금 번호인지 확인해, 지난 Task 가 새 Task 의 상태를 덮지 않게 한다.
  private func index(with indexing: any IndexingClient, generation: Int) async {
    guard self.isCurrent(generation) else { return }
    self.isIndexingStopped = false
    self.isIndexing = true
    for await progress in indexing.run() {
      guard self.isCurrent(generation) else { return }
      self.indexingProgress = progress
      self.isIndexing = !progress.isFinished
      // 개수를 다시 읽기 전에 올려 저장소를 읽는 열린 화면(카테고리 화면·기프티콘·영수증 목록·여행 폴더 목록·상세·사진 상세·검색)의 다시 읽기가 함께 시작되게 한다.
      self.storeRevision += 1
      await self.refreshCategoryCounts(generation: generation)
      self.requestReminderSync()
    }
    guard self.isCurrent(generation) else { return }
    self.isIndexing = false
    // 화면이 사라져 구독을 끝낸 것은 멈춘 것이 아니다.
    guard !Task.isCancelled else { return }
    // 마지막 진행률 뒤에 저장소를 바꾸고(삭제 등) 멈췄을 수 있으므로 한 번 더 읽는다.
    await self.refreshCategoryCounts(generation: generation)
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    self.storeRevision += 1
    self.requestReminderSync()
    self.isIndexingStopped = true
  }

  /// 저장소를 읽지 못하면 지난 개수를 그대로 둔다. 인덱싱도 같은 저장소를 쓰므로 멈춤 안내로 드러난다.
  private func refreshCategoryCounts(generation: Int) async {
    guard let photoStore = self.photoStore else { return }
    do throws(PhotoStoreError) {
      var counts = try await photoStore.categoryCounts()
      let tripCount = try await photoStore.tripCount()
      if tripCount > 0 {
        counts[.travel] = tripCount
      }
      guard self.isCurrent(generation) else { return }
      self.categoryCounts = counts
    } catch {
      return
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.indexingGeneration
  }

  /// 동기화 요청을 하나씩 차례로 처리해 동기화가 겹치지 않게 한다. 도는 중 들어온 요청 여러 개는 끝난 뒤 한 번으로 합친다
  /// (요청은 "지금 상태로 다시 맞춰라"라서 합쳐도 된다). 알림이나 저장소가 없으면 시작하지 않는다.
  private func runReminderSync() async {
    guard let notification = self.notification, let photoStore = self.photoStore else { return }
    self.reminderGeneration += 1
    let generation = self.reminderGeneration
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.reminderSyncRequests = continuation
    // 화면 진입 동기화.
    continuation.yield()
    for await _ in requests {
      guard self.isCurrentReminderSync(generation) else { return }
      await self.syncReminders(notification: notification, photoStore: photoStore, generation: generation)
    }
  }

  private func requestReminderSync() {
    self.reminderSyncRequests?.yield()
  }

  /// 권한을 읽고, 저장소의 만료 예정으로 원하는 알림을 계산해 대기 알림과의 식별자 차이만 지우고 더한다.
  /// 저장소를 읽지 못하거나 추출 대기가 있으면 예약을 바꾸지 않는다(판단은 `ExpiryReminderPlanner.changes`,
  /// docs/ARCHITECTURE.md §4 만료 알림). 기다린 뒤에는 늘 지금 번호인지 확인해, 지난 루프가 상태와 예약을 바꾸지 않게 한다.
  /// 같은 읽기로 위젯에 보일 요약을 계산해, 지난 요청 때와 다를 때만 위젯 갱신을 요청한다(알림 권한과 관계없이,
  /// docs/ARCHITECTURE.md §4 만료 임박 위젯). 저장소를 읽지 못하면 요청하지 않는다.
  private func syncReminders(
    notification: any NotificationClient,
    photoStore: any PhotoStoreClient,
    generation: Int
  ) async {
    // 권한 요청과 겹쳐 요청 전에 읽은 값이거나 팝업 중에 읽은 값(미정)이면 상태를 덮지 않는다.
    // 아래 판단도 이번에 읽은 값으로 해, 지난 값이면 예약하지 않고 요청이 끝난 뒤의 동기화에 맡긴다.
    let requestCount = self.authorizationRequestCount
    let wasRequesting = self.isRequestingNotificationAuthorization
    let status = await notification.authorizationStatus()
    guard self.isCurrentReminderSync(generation) else { return }
    if requestCount == self.authorizationRequestCount, !wasRequesting, !self.isRequestingNotificationAuthorization {
      self.notificationAuthorization = status
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
    guard self.isCurrentReminderSync(generation) else { return }
    self.requestWidgetReloadIfChanged(expiries: expiries, isChecking: !pendingExtractionIDs.isEmpty, now: now)
    let desired = ExpiryReminderPlanner.reminders(for: expiries, now: now, calendar: self.calendar)
      .map { $0.notificationRequest(calendar: self.calendar) }
    self.hasPlannedReminder = !desired.isEmpty

    // `changes` 가 nil 을 낼 조건이면 알림 센터를 부르지 않는다.
    guard status == .authorized, pendingExtractionIDs.isEmpty, !Task.isCancelled else { return }
    let pendingIDs = await notification.pendingRequestIDs()
    guard self.isCurrentReminderSync(generation), !Task.isCancelled,
          let changes = ExpiryReminderPlanner.changes(
            desiredIDs: Set(desired.map(\.id)),
            pendingIDs: pendingIDs,
            managedPrefix: ExpiryReminder.notificationIDPrefix,
            isAuthorized: status == .authorized,
            hasPendingExtraction: !pendingExtractionIDs.isEmpty
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

  private func isCurrentReminderSync(_ generation: Int) -> Bool {
    generation == self.reminderGeneration
  }

  /// 비교와 요청 사이에 기다리지 않아 겹치지 않는다. 요약에 날짜가 들어 있어 자정을 넘기면(`dayChanged`) 하루 한 번 더 요청한다.
  private func requestWidgetReloadIfChanged(expiries: [GifticonExpiry], isChecking: Bool, now: Date) {
    guard let widgetTimeline = self.widgetTimeline else { return }
    let summaries = ExpiryWidgetTimeline.summaries(
      for: expiries,
      isChecking: isChecking,
      today: LocalDate(now, calendar: self.calendar)
    )
    guard summaries != self.requestedWidgetSummaries else { return }
    self.requestedWidgetSummaries = summaries
    widgetTimeline.reloadExpiryWidget()
  }

  /// 권한 상태도 다시 읽어, 앱 실행 중 설정에서 바뀐 제한 접근 상태를 배너에 반영한다.
  private func reloadImages() async {
    self.refreshLimitedAccess()
    self.imageIDs = await Set(self.photoLibrary.fetchImageAssets().map(\.id))
  }

  private func refreshLimitedAccess() {
    self.isLimited = self.photoLibrary.accessState() == .limited
  }
}
