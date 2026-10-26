import Core
import Foundation
import Observation
import PhotoLibraryInterface
import PhotoStoreInterface

/// 정리 화면의 상태와 로직 (docs/ARCHITECTURE.md §4 정리 도우미). 만료된 기프티콘과 사용한 기프티콘, 비슷한 사진 묶음을 후보로 보이고,
/// 고른 것을 시스템 확인 창을 거쳐 보관함에서 지운다. 비슷한 사진은 이 기기에서 특징 벡터를 만들 수 있을 때만 읽는다(`findsSimilarPhotos`).
/// 화면은 한 번에 하나만 열리므로 App 이 하나를 소유한다. 화면을 새로 열 때마다 View 가 새 방문 번호(`visit`)를 넘겨
/// 선택·안내·이번 방문에 지운 목록을 비운다. 사진 상세에서 돌아오면 같은 방문이라 그대로 둔다.
/// 저장소 변경·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
@MainActor
@Observable
public final class CleanupModel {
  /// 후보 목록. 이번 방문에 지웠거나 건너뛴 결과를 받은 이미지는 빠져 있다.
  public private(set) var content: CleanupContent = .loading
  /// 고른 후보. 늘 `content` 의 후보 안에 있다.
  public private(set) var selectedIDs: Set<ImageAsset.ID> = []
  /// 시스템 확인 창을 거쳐 지우는 중. 결과가 와야 풀린다.
  public private(set) var isDeleting = false
  /// 마지막 삭제의 결과 안내.
  public private(set) var notice: CleanupNotice?
  public private(set) var alert: CleanupAlert?
  /// 제한 접근이라 고른 사진 안에서만 정리한다.
  public private(set) var isLimited: Bool
  /// 만료 판정의 기준. 기기 시간대의 오늘.
  public private(set) var today: LocalDate
  /// 만료일 표시가 쓰는 기기 달력의 사본. `GifticonListModel.calendar` 와 같은 이유로 담는다.
  public private(set) var calendar: Calendar
  /// 지금 방문 번호. 화면(View)이 새로 열릴 때마다 다르다.
  public private(set) var visit: UUID?

  /// 고른 후보 수.
  public var selectionCount: Int {
    self.selectedCandidates.count
  }

  /// 고른 후보를 지우면 확보될 저장 공간의 추정 바이트.
  public var selectionBytes: Int64 {
    CleanupSizeEstimate.bytes(of: self.selectedCandidates.map(\.asset))
  }

  /// 마지막으로 읽은 저장소 목록. 날짜가 바뀌면 이 목록으로 후보를 다시 가른다.
  @ObservationIgnored private var items: [GifticonListItem] = []
  /// 마지막으로 읽은 비슷한 사진 묶기 입력(시간 이웃이 있는 사진과 벡터). 사진에서 만든 값이라 로그에 남기지 않는다.
  @ObservationIgnored private var similarPhotos: [FeaturePrintedPhoto] = []
  /// 마지막으로 읽은, 아직 비교하지 않은 대상 사진 수.
  @ObservationIgnored private var uncomparedPhotoCount = 0
  /// `similarPhotos` 에서 이번 방문에 지운 것과 기프티콘을 빼고 묶은 결과. 읽거나 숨긴 목록이 바뀔 때만 다시 묶는다(`regroup()`).
  @ObservationIgnored private var similarGroups: [SimilarPhotoGroup] = []
  /// 이번 방문에 지웠거나 건너뛴 식별자. 저장소 반영이 늦어도 다시 보이지 않게 한다.
  @ObservationIgnored private var hiddenIDs: Set<ImageAsset.ID> = []
  /// 앱을 켜 둔 동안 지운(또는 건너뛴) 식별자 중 저장소가 아직 돌려주는 것. 다음 방문의 기본 선택에서 뺀다.
  /// 최근 삭제에서 복구한 사진이면 행이 계속 돌려지므로 숨기지 않고 해제 상태로 보인다.
  @ObservationIgnored private var recentlyDeletedIDs: Set<ImageAsset.ID> = []
  /// 이번 방문의 첫 읽기에서 기본 선택을 했는지. 나중에 나타난 후보는 선택하지 않고 사용자가 보고 고르게 한다.
  @ObservationIgnored private var hasLoadedInVisit = false
  /// `onAppear(visit:)` 를 시작할 때마다 하나씩 올린다. 화면을 닫았다 바로 열면 지난 Task 가 늦게 깨어날 수 있으므로,
  /// 내용은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안(`onAppear(visit:)` 가 구독하는 동안)만 있다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let findsSimilarPhotos: Bool
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다(그때는 정리 줄이 없어 이 화면에 오지 않는다).
  ///   - findsSimilarPhotos: 비슷한 사진 섹션을 보일지. App 이 `ImageAnalysisClient.isFeaturePrintAvailable` 을 넘긴다(시뮬레이터는 false).
  ///     false 면 비슷한 사진을 조회하지 않아 섹션과 미비교 안내가 없다. 실행 도중 벡터를 쓸 수 없게 되어도 저장된 벡터로 묶음은 보인다.
  ///   - calendar: 기기 달력. 읽을 때와 `dayChanged()` 때 부른다.
  ///   - now: 지금 시각. 읽을 때와 `dayChanged()` 때 부른다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    photoStore: (any PhotoStoreClient)?,
    findsSimilarPhotos: Bool = false,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.photoLibrary = photoLibrary
    self.photoStore = photoStore
    self.findsSimilarPhotos = findsSimilarPhotos
    self.currentCalendar = calendar
    self.now = now
    let current = calendar()
    self.calendar = current
    self.today = LocalDate(now(), calendar: current)
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  /// 후보를 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 새 방문이면 선택·안내·이번 방문에 지운 목록을 비우고, 같은 방문(사진 상세에서 돌아옴)이면 둔 채 한 번 다시 읽는다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  public func onAppear(visit: UUID) async {
    self.generation += 1
    let generation = self.generation
    self.refreshLimited()
    if self.visit != visit {
      self.visit = visit
      self.selectedIDs = []
      self.hiddenIDs = []
      self.hasLoadedInVisit = false
      self.notice = nil
      self.alert = nil
      self.content = .loading
    } else if self.content == .failed {
      self.content = .loading
    }
    guard let photoStore = self.photoStore else {
      self.content = .failed
      return
    }
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.reloadRequests = continuation
    // 처음 읽기.
    continuation.yield()
    for await _ in requests {
      guard self.isCurrent(generation) else { return }
      await self.reload(photoStore: photoStore, generation: generation)
    }
    // 화면이 닫혔다. 이후 신호와 다시 시도는 버리고, 다음 진입이 처음 읽기를 한다.
    if self.isCurrent(generation) {
      self.reloadRequests = nil
    }
  }

  /// 저장소 내용(추출 값·사용 여부·보관함 삭제)이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 날짜나 시간대가 바뀌었다(자정을 넘김, 시간대 변경, 앱 복귀). 저장소는 읽지 않고 오늘과 달력만 다시 계산해,
  /// 오늘이 바뀌었으면 마지막으로 읽은 목록으로 후보를 다시 가른다(새로 만료된 후보는 선택하지 않는다).
  /// 화면이 닫혀 있어도 계산해, 다음에 열 때 지난 날짜로 그리지 않는다. 앱 복귀가 부르므로 제한 접근 상태도 다시 읽는다.
  public func dayChanged() {
    let isNewDay = self.refreshDay()
    self.refreshLimited()
    if isNewDay, case .loaded = self.content {
      self.apply()
    }
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 후보 하나를 고르거나 푼다. 목록에 없는 식별자는 무시한다. 삭제 중에도 받는다(삭제 요청은 이미 고른 목록을 보냈다).
  public func candidateToggled(id: ImageAsset.ID) {
    guard case let .loaded(sections) = self.content, sections.candidateIDs.contains(id) else { return }
    if self.selectedIDs.contains(id) {
      self.selectedIDs.remove(id)
    } else {
      self.selectedIDs.insert(id)
    }
  }

  /// 섹션의 "모두 선택" 대상(`bulkSelectableIDs`, 비슷한 사진은 남길 장을 뺀 것)이 모두 골라져 있으면 섹션 후보를 모두 풀고,
  /// 아니면 그 대상을 모두 고른다.
  public func sectionSelectionToggled(_ kind: CleanupSection.Kind) {
    guard case let .loaded(sections) = self.content,
          let section = sections.sections.first(where: { $0.kind == kind })
    else { return }
    let selectable = section.bulkSelectableIDs
    if selectable.isSubset(of: self.selectedIDs) {
      self.selectedIDs.subtract(section.candidates.map(\.id))
    } else {
      self.selectedIDs.formUnion(selectable)
    }
  }

  /// 고른 후보를 지운다: 시스템 확인 창이 떠 있는 동안 기다리고, 결과대로 목록·선택·안내를 바꾼다.
  /// 취소하면 아무것도 바꾸지 않는다. 실패하면 알림 창을 띄우고 선택을 둔다. 지우는 중에는 다시 누를 수 없다.
  /// 결과가 올 때 화면이 이미 새 방문이면 안내는 띄우지 않고, 성공한 결과의 지웠거나 건너뛴 식별자만 지금 방문의 목록·선택에서 뺀다.
  public func deleteButtonTapped() async {
    guard !self.isDeleting, case .loaded = self.content, !self.selectedIDs.isEmpty else { return }
    let requested = self.selectedIDs
    let requestVisit = self.visit
    self.isDeleting = true
    let result: ImageDeletionResult
    do throws(ImageDeletionError) {
      result = try await self.photoLibrary.deleteImages(ids: requested)
    } catch {
      self.isDeleting = false
      guard self.visit == requestVisit else { return }
      switch error {
      case .userCancelled: break
      case .notAuthorized: self.alert = .deleteNotAuthorized
      case .failed: self.alert = .deleteFailed
      }
      return
    }
    let gone = result.deletedIDs.union(result.skippedIDs)
    self.recentlyDeletedIDs.formUnion(gone)
    self.isDeleting = false
    // 새 방문의 첫 읽기가 결과보다 먼저 끝났을 수 있다. 저장소는 아직 그 행을 돌려주므로 지금 방문에서도 숨기고 선택에서 뺀다.
    self.hiddenIDs.formUnion(gone)
    self.selectedIDs.subtract(gone)
    if self.visit == requestVisit {
      self.notice = CleanupNotice(deletedCount: result.deletedIDs.count, skippedCount: result.skippedIDs.count)
    }
    if case .loaded = self.content {
      self.regroup()
      self.apply()
    }
  }

  public func alertDismissed() {
    self.alert = nil
  }

  public func noticeDismissed() {
    self.notice = nil
  }

  /// 제한 접근에서 사진 선택 화면을 띄운다. 고른 사진이 바뀌면 인덱서가 저장소를 맞추고 재조회로 이어진다.
  public func selectMorePhotosTapped() async {
    await self.photoLibrary.presentLimitedLibraryPicker()
    self.refreshLimited()
  }

  // MARK: - Private

  private var selectedCandidates: [CleanupCandidate] {
    guard case let .loaded(sections) = self.content else { return [] }
    return sections.sections.flatMap(\.candidates).filter { self.selectedIDs.contains($0.id) }
  }

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 기프티콘과 (`findsSimilarPhotos` 면) 비슷한 사진을 차례로 읽고, 둘 다 성공해야 반영한다.
  /// 다시 읽기에 실패하면 지난 목록을 둔다(저장소 문제는 보관함 화면의 인덱싱 멈춤 안내가 알린다).
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    self.refreshDay()
    let items: [GifticonListItem]
    var entries: SimilarPhotoEntries?
    do throws(PhotoStoreError) {
      items = try await photoStore.gifticons()
      if self.findsSimilarPhotos {
        guard self.isCurrent(generation), !Task.isCancelled else { return }
        entries = try await photoStore.similarPhotoEntries()
      }
    } catch {
      self.refreshLimited()
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      if case .loaded = self.content {
        return
      }
      self.content = .failed
      return
    }
    self.refreshLimited()
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    self.items = items
    self.similarPhotos = entries?.photos ?? []
    self.uncomparedPhotoCount = entries?.uncomparedCount ?? 0
    // 인덱서가 행을 지웠다. 같은 식별자가 다시 들어오면(복구) 다음 방문에서 다시 기본 선택이 될 수 있다.
    self.recentlyDeletedIDs.formIntersection(items.map(\.id) + self.similarPhotos.map(\.id))
    self.regroup()
    self.apply()
  }

  /// 이번 방문에 지운 사진을 빼고 비슷한 사진을 묶는다. 기프티콘 카테고리 이미지는 후보가 아니어도 뺀다
  /// (같은 템플릿의 다른 기프티콘이 묶여 미사용 기프티콘이 기본 선택되지 않게). 날짜와 무관해 `dayChanged()` 는 부르지 않는다.
  /// 앱을 켜 둔 동안 지운 사진(`recentlyDeletedIDs`)은 저장소가 아직 돌려줘도 남길 장으로 고르지 않는다
  /// (지운 장이 남김이 되어 실제로 남은 장이 모두 기본 선택되지 않게).
  private func regroup() {
    let visible = self.similarPhotos.filter { !self.hiddenIDs.contains($0.id) }
    self.similarGroups = SimilarPhotoGrouping.groups(
      visible,
      excluding: Set(self.items.map(\.id)),
      unkeepable: self.recentlyDeletedIDs
    )
  }

  /// `items`·`similarGroups` 에서 이번 방문에 지운 것을 빼고 후보를 가른다.
  /// 방문의 첫 읽기에서만 기본 선택을 주고, 그 뒤에 나타난 후보는 선택하지 않는다. 사라진 후보는 선택에서도 뺀다.
  /// 진행률 대부분은 후보를 바꾸지 않으므로, 같으면 대입하지 않아 다시 그리지 않는다.
  private func apply() {
    let visible = self.items.filter { !self.hiddenIDs.contains($0.id) }
    let sections = CleanupSections.make(
      gifticons: visible,
      today: self.today,
      similarPhotoGroups: self.similarGroups,
      uncomparedPhotoCount: self.uncomparedPhotoCount
    )
    if !self.hasLoadedInVisit {
      let defaults = sections.sections.flatMap(\.candidates)
        .filter { $0.isSelectedByDefault && !self.recentlyDeletedIDs.contains($0.id) }
        .map(\.id)
      self.selectedIDs = Set(defaults)
      self.hasLoadedInVisit = true
    }
    let kept = self.selectedIDs.intersection(sections.candidateIDs)
    if kept != self.selectedIDs {
      self.selectedIDs = kept
    }
    guard self.content != .loaded(sections) else { return }
    self.content = .loaded(sections)
  }

  /// 같으면 대입하지 않아 다시 그리지 않는다. 오늘이 바뀌었으면 true.
  @discardableResult
  private func refreshDay() -> Bool {
    let calendar = self.currentCalendar()
    let today = LocalDate(self.now(), calendar: calendar)
    if self.calendar != calendar {
      self.calendar = calendar
    }
    guard self.today != today else { return false }
    self.today = today
    return true
  }

  private func refreshLimited() {
    let isLimited = self.photoLibrary.accessState() == .limited
    if self.isLimited != isLimited {
      self.isLimited = isLimited
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }
}
