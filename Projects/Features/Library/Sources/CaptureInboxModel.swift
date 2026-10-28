import Core
import Foundation
import Observation
import PhotoLibraryInterface
import PhotoStoreInterface

/// 최근 스크린샷 화면의 상태와 로직 (docs/ARCHITECTURE.md §4 정리 도우미). 최근 30일의 보관하지 않은 스크린샷을
/// 한 장씩 "보관"하거나 "삭제 표시"하고, 표시한 것을 모아 한 번에 지운다.
/// 보관은 누르는 즉시 저장소에 저장하고, 삭제 표시는 화면이 열려 있는 동안(방문)만 갖는다. 이 화면은 다른 화면을 push 하지 않으므로
/// 새로 열 때마다 새 방문이고, 방문 번호(`visit`)를 View 가 넘겨 표시·안내·이번 방문에 처리한 목록을 비운다.
/// 화면은 한 번에 하나만 열리므로 App 이 하나를 소유한다.
/// 저장소 변경·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
@MainActor
@Observable
public final class CaptureInboxModel {
  /// 대상 목록, 최신순. 이번 방문에 보관했거나 지웠거나 건너뛴 결과를 받은 이미지는 빠져 있다.
  public private(set) var content: CaptureInboxContent = .loading
  /// 삭제 표시한 이미지, 표시한 순서. 늘 `content` 안에 있다.
  public private(set) var markedIDs: [ImageAsset.ID] = []
  /// 보관을 저장하는 중인 이미지.
  public private(set) var keepingID: ImageAsset.ID?
  /// 시스템 확인 창을 거쳐 지우는 중. 결과가 와야 풀린다.
  public private(set) var isDeleting = false
  /// 마지막 삭제의 결과 안내.
  public private(set) var notice: CleanupNotice?
  public private(set) var alert: CleanupAlert?
  /// 제한 접근이라 고른 사진 안에서만 정리한다.
  public private(set) var isLimited: Bool
  /// 지금 방문 번호. 화면(View)이 새로 열릴 때마다 다르다.
  public private(set) var visit: UUID?
  /// 이번 방문에 보관한 수. 위치 표시("n / 전체")가 보관한 장을 빼도 전체 수가 줄지 않게 한다.
  public private(set) var keptCount = 0

  /// 삭제 표시를 하지 않은 첫 장(최신순). 없으면 모두 확인했거나 대상이 없다.
  public var current: ImageAsset? {
    guard case let .loaded(assets) = self.content else { return nil }
    let marked = Set(self.markedIDs)
    return assets.first { !marked.contains($0.id) }
  }

  /// 화면의 "n / 전체". 지금 장이 없으면 nil.
  public var position: (index: Int, total: Int)? {
    guard case let .loaded(assets) = self.content,
          let current = self.current,
          let index = assets.firstIndex(of: current)
    else { return nil }
    return (self.keptCount + index + 1, self.keptCount + assets.count)
  }

  /// 표시한 이미지를 지우면 확보될 저장 공간의 추정 바이트.
  public var markedBytes: Int64 {
    guard case let .loaded(assets) = self.content else { return 0 }
    let marked = Set(self.markedIDs)
    return CleanupSizeEstimate.bytes(of: assets.filter { marked.contains($0.id) })
  }

  /// 마지막으로 읽은 저장소 목록.
  @ObservationIgnored private var items: [ImageAsset] = []
  /// 이번 방문에 보관했거나 지웠거나 건너뛴 식별자. 저장소 반영이 늦어도 다시 보이지 않게 한다.
  @ObservationIgnored private var hiddenIDs: Set<ImageAsset.ID> = []
  /// `onAppear(visit:)` 를 시작할 때마다 하나씩 올린다. 화면을 닫았다 바로 열면 지난 Task 가 늦게 깨어날 수 있으므로,
  /// 내용은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안(`onAppear(visit:)` 가 구독하는 동안)만 있다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다(그때는 정리 줄이 없어 이 화면에 오지 않는다).
  ///   - calendar: 기기 달력. 기간의 시작을 정할 때 부른다.
  ///   - now: 지금 시각. 기간의 시작을 정할 때 부른다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    photoStore: (any PhotoStoreClient)?,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.photoLibrary = photoLibrary
    self.photoStore = photoStore
    self.currentCalendar = calendar
    self.now = now
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  /// 대상을 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 새 방문이면 표시·안내·이번 방문에 처리한 목록을 비운다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  public func onAppear(visit: UUID) async {
    self.generation += 1
    let generation = self.generation
    self.refreshLimited()
    if self.visit != visit {
      self.visit = visit
      self.markedIDs = []
      self.hiddenIDs = []
      self.keptCount = 0
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

  /// 저장소 내용(보관함 삭제 포함)이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 날짜나 시간대가 바뀌었다(자정을 넘김, 시간대 변경, 앱 복귀). 기간의 시작이 바뀌므로 화면이 열려 있으면 다시 읽는다.
  /// 앱 복귀가 부르므로 제한 접근 상태도 다시 읽는다.
  public func dayChanged() {
    self.refreshLimited()
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 지금 장을 보관한다: 저장소에 저장하고 목록에서 뺀다. 행이 이미 없어도(보관함에서 빠짐) 목록에서 뺀다.
  /// 저장하는 중이거나 지우는 중에는 무시한다. 저장에 실패하면 알림 창을 띄우고 장은 그대로 둔다.
  /// 결과가 올 때 화면이 이미 새 방문이면 그 방문의 상태에는 반영하지 않는다. 성공이면 새 방문의 첫 읽기가 저장 전에
  /// 끝났을 수 있고 보관은 저장소 변경 신호를 내지 않으므로, 열려 있는 방문을 한 번 다시 읽는다.
  public func keepTapped() async {
    guard self.keepingID == nil, !self.isDeleting, let id = self.current?.id,
          let photoStore = self.photoStore, let requestVisit = self.visit
    else { return }
    self.keepingID = id
    do throws(PhotoStoreError) {
      _ = try await photoStore.keepInCaptureInbox(id: id)
    } catch {
      self.finishKeeping(id: id)
      if self.visit == requestVisit {
        self.alert = .keepFailed
      }
      return
    }
    self.finishKeeping(id: id)
    guard self.visit == requestVisit else {
      self.reloadRequests?.yield()
      return
    }
    self.hiddenIDs.insert(id)
    self.keptCount += 1
    self.apply()
  }

  /// 지금 장을 삭제 표시한다. 보관을 저장하는 중에는 무시한다.
  public func markForDeletionTapped() {
    guard self.keepingID == nil, let id = self.current?.id else { return }
    self.markedIDs.append(id)
  }

  /// 삭제 표시를 푼다. 표시하지 않은 식별자는 무시한다. 삭제 중에도 받는다(삭제 요청은 이미 표시한 목록을 보냈다).
  public func unmarkTapped(id: ImageAsset.ID) {
    self.markedIDs.removeAll { $0 == id }
  }

  /// 삭제 표시한 이미지를 지운다: 시스템 확인 창이 떠 있는 동안 기다리고, 결과대로 목록·표시·안내를 바꾼다.
  /// 취소하면 아무것도 바꾸지 않는다. 실패하면 알림 창을 띄우고 표시를 둔다. 지우는 중에는 다시 누를 수 없다.
  /// 결과가 올 때 화면이 이미 새 방문이면 안내는 띄우지 않고, 성공한 결과의 지웠거나 건너뛴 장만 지금 방문의 목록·표시에서 뺀다.
  public func deleteButtonTapped() async {
    guard !self.isDeleting, case .loaded = self.content, !self.markedIDs.isEmpty else { return }
    let requested = Set(self.markedIDs)
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
    self.isDeleting = false
    let gone = result.deletedIDs.union(result.skippedIDs)
    // 새 방문의 첫 읽기가 결과보다 먼저 끝났을 수 있다. 저장소는 아직 그 행을 돌려주므로 지금 방문에서도 숨기고 표시에서 뺀다.
    self.hiddenIDs.formUnion(gone)
    self.markedIDs.removeAll { gone.contains($0) }
    if self.visit == requestVisit {
      self.notice = CleanupNotice(deletedCount: result.deletedIDs.count, skippedCount: result.skippedIDs.count)
    }
    if case .loaded = self.content {
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

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 다시 읽기에 실패하면 지난 목록을 둔다(저장소 문제는 보관함 화면의 인덱싱 멈춤 안내가 알린다).
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    // 기간의 시작을 계산하지 못하면 대상이 없는 것으로 본다.
    guard let start = CaptureInboxWindow.start(now: self.now(), calendar: self.currentCalendar()) else {
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      self.items = []
      self.apply()
      return
    }
    let assets: [ImageAsset]
    do throws(PhotoStoreError) {
      assets = try await photoStore.captureInboxScreenshots(createdSince: start)
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
    self.items = assets
    self.apply()
  }

  /// `items` 에서 이번 방문에 처리한 것을 빼 보인다. 재조회로 사라진 이미지는 삭제 표시에서도 뺀다.
  /// 진행률 대부분은 대상을 바꾸지 않으므로, 같으면 대입하지 않아 다시 그리지 않는다.
  private func apply() {
    let visible = self.items.filter { !self.hiddenIDs.contains($0.id) }
    let visibleIDs = Set(visible.map(\.id))
    let marked = self.markedIDs.filter { visibleIDs.contains($0) }
    if marked != self.markedIDs {
      self.markedIDs = marked
    }
    guard self.content != .loaded(visible) else { return }
    self.content = .loaded(visible)
  }

  /// 다음 방문이 같은 장의 보관을 시작하지 못하게 막던 표시를, 내 것일 때만 푼다.
  private func finishKeeping(id: ImageAsset.ID) {
    if self.keepingID == id {
      self.keepingID = nil
    }
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
