import Core
import Foundation
import Observation
import PhotoLibraryInterface
import PhotoStoreInterface

/// 카테고리 화면(월별 썸네일 격자, 쇼핑·대화·지도는 쇼핑몰·브랜드·앱·지역별 묶기 포함)과 사진 상세 이미지의 상태와 로직
/// (docs/ARCHITECTURE.md §4 카테고리 화면). 쇼핑·대화·지도는 `captureGroupItems(in:)` 로 읽어 월별과 묶기별 섹션을 함께 만들고,
/// 어느 묶기를 보일지는 View 의 화면 일시 상태다.
/// 카테고리 화면은 한 번에 하나만 열리므로 App 이 하나를 소유하고, 열 때마다 `onAppear(category:)` 로 다시 쓴다.
/// 기프티콘·영수증 목록(`GifticonListView`·`ReceiptListView`)은 격자 대신 `GifticonListModel`·`ReceiptListModel` 이,
/// 여행 폴더 목록·상세(`TripListView`·`TripDetailView`)는 `TripListModel`·`TripDetailModel` 이 내용을 읽고,
/// 보관함 검색 결과(`SearchResultsView`, `SearchModel`)도 썸네일 칸을 `thumbnailScreenAppeared(scope: .search)` 로 빌리고,
/// 정리 화면·캡처 인박스(`CleanupView`·`CaptureInboxView`)는 `thumbnailScreenAppeared(scope: .cleanup)` 로 빌린다.
/// 썸네일 칸은 `thumbnailScreenAppeared(category:)` 로 이 Model 의 보관 규칙을 그대로 쓴다.
/// 상세는 카테고리 화면·기프티콘 목록·영수증 목록·여행 폴더 상세·정리 화면 위에서만 열리므로 상세 이미지도 여기서 갖는다
/// (캡처 인박스는 상세를 push 하지 않고 지금 장을 같은 읽기 `detailAppeared(id:)` 로 크게 보인다)
/// (상세의 캡처 행동은 `CaptureActionsModel`).
/// 저장소 변경 신호는 LibraryView 가 `LibraryModel.storeRevision` 변화를 `libraryStoreChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
@MainActor
@Observable
public final class CategoryModel {
  /// 지금(또는 마지막으로) 썸네일 칸을 쓰는 화면. 열기 전에는 nil.
  public private(set) var thumbnailScope: ThumbnailScope?
  /// 지금(또는 마지막으로) 연 카테고리. 열기 전이나 검색 결과 화면이 칸을 쓰는 동안에는 nil.
  public var category: ImageCategory? {
    if case let .category(category) = self.thumbnailScope {
      category
    } else {
      nil
    }
  }

  /// 격자 내용. 다른 카테고리를 열면 `.loading` 부터, 같은 카테고리를 다시 열면 지난 내용을 둔 채 다시 읽는다.
  public private(set) var content: CategoryContent = .loading {
    didSet { self.contentRevision += 1 }
  }

  /// 보이는 칸과 최근에 사라진 칸의 썸네일. 읽는 중에 칸이 사라지면 빠지고, 읽은 썸네일은 칸이 사라져도
  /// 최근 `retainedThumbnailLimit` 장까지 남았다가 오래된 것부터 빠진다. 다른 카테고리를 열면 모두 빠진다.
  /// 메모리는 살아 있는 칸 수 + `retainedThumbnailLimit` 장을 넘지 않는다.
  public private(set) var thumbnails: [ImageAsset.ID: ImageLoadState] = [:]
  /// 열린 상세. 상세의 Task 가 끝나면(닫히면) nil 이 되어 가장 큰 버전 이미지를 놓는다.
  public private(set) var detail: PhotoDetail?

  /// `onAppear(category:)` 를 시작할 때마다 하나씩 올린다. 화면을 닫았다 바로 열거나 다른 카테고리를 열면
  /// 지난 Task 가 늦게 깨어날 수 있으므로, 내용은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안(`onAppear(category:)` 가 구독하는 동안)만 있다.
  /// 상세가 열려 있는 동안은 카테고리 화면의 `.task` 도 끝나 없다. 그동안 온 신호는 버리고, 돌아오면 한 번 다시 읽는다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?
  /// 이미지마다 지금 주인인 칸들의 요청 번호. 사라졌다 다시 보인 칸에서 지난 Task 의 늦은 결과·정리가 지금 상태를 바꾸지 않게 한다.
  /// 지역별 묶기에서는 같은 이미지가 두 섹션에 보일 수 있어 칸이 여럿일 수 있다.
  @ObservationIgnored private var thumbnailOwners: [ImageAsset.ID: Set<Int>] = [:]
  @ObservationIgnored private var thumbnailRequestCount = 0
  /// 칸의 Task 가 끝났지만 아직 놓지 않은 썸네일 식별자. 오래된 것부터. `thumbnails` 에 `.loaded` 로 있고 주인(`thumbnailOwners`)이 없다.
  @ObservationIgnored private var retainedThumbnailIDs: [ImageAsset.ID] = []
  /// `content` 를 바꿀 때마다 오른다. 메인 밖에서 섹션을 비교하는 동안 내용이 바뀌었으면 그 비교 결과를 쓰지 않는다.
  @ObservationIgnored private var contentRevision = 0
  /// 상세를 열 때마다 하나씩 올린다. 닫은 뒤 바로 다른(또는 같은) 사진을 열어도 지난 Task 가 지금 상세를 바꾸지 않게 한다.
  @ObservationIgnored private var detailRequestCount = 0

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private let sectioning: Sectioning

  /// 사라진 칸의 썸네일을 이만큼까지 남긴다. 상세를 열면 아래 격자의 칸 Task 가 모두 취소되므로, 돌아왔을 때 다시 읽지 않게
  /// 한 화면의 칸 수(약 48)보다 크게 둔다. 썸네일 한 장은 긴 변 512px 로 최대 약 1MB(4:3 사진은 약 0.8MB)라,
  /// 보관분은 최대 약 64MB(4:3 사진은 약 50MB)다.
  static let retainedThumbnailLimit = 64

  /// 다시 읽은 목록을 섹션으로 만들고 지금 섹션과 비교하는 단계. 테스트가 이 단계에서 멈출 수 있게 주입한다.
  typealias Sectioning = @Sendable (CategoryItems, Calendar, CategorySections?) async
    -> (sections: CategorySections, isUnchanged: Bool)

  /// - Parameters:
  ///   - photoLibrary: 사진 보관함. 썸네일과 상세 이미지를 읽는다.
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다.
  ///   - calendar: 월 섹션을 나누는 기기 달력·시간대.
  public convenience init(
    photoLibrary: any PhotoLibraryClient,
    photoStore: (any PhotoStoreClient)?,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.init(
      photoLibrary: photoLibrary,
      photoStore: photoStore,
      calendar: calendar,
      sectioning: CategorySectioning.sections
    )
  }

  /// - Parameter sectioning: 섹션 계산·비교. 공개 init 은 메인 밖에서 도는 `CategorySectioning.sections` 를 쓴다.
  init(
    photoLibrary: any PhotoLibraryClient,
    photoStore: (any PhotoStoreClient)?,
    calendar: Calendar = .autoupdatingCurrent,
    sectioning: @escaping Sectioning
  ) {
    self.photoLibrary = photoLibrary
    self.photoStore = photoStore
    self.calendar = calendar
    self.sectioning = sectioning
  }

  // MARK: - Events

  /// 카테고리를 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  /// 상세에서 돌아오거나 같은 카테고리를 다시 열면 지난 격자와 썸네일을 둔 채 한 번 다시 읽는다.
  public func onAppear(category: ImageCategory) async {
    self.generation += 1
    let generation = self.generation
    if self.thumbnailScope != .category(category) {
      self.switchScope(to: .category(category))
    } else if self.content == .failed {
      self.content = .loading
    }
    // 저장소가 없으면 다시 시도할 수 없어 버튼이 반응하지 않는다. App 은 저장소가 없으면 카테고리 줄을 보이지 않아
    // (LibraryModel 의 개수가 빈다) 이 화면에 오지 않고, Example·Preview 도 저장소 없이 이 화면을 띄우지 않으므로 상태를 따로 두지 않는다.
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
      await self.reload(category, photoStore: photoStore, generation: generation)
    }
    // 화면이 닫혔다. 이후 신호와 다시 시도는 버리고, 다음 진입이 처음 읽기를 한다.
    if self.isCurrent(generation) {
      self.reloadRequests = nil
    }
  }

  /// 저장소 내용이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 격자가 아닌 화면(기프티콘·영수증 목록, 여행 폴더 목록·상세)이 이 카테고리의 썸네일 칸을 쓰는 동안(View `.task` 수명) 기다린다. 저장소를 읽지 않는다.
  /// 다른 카테고리였으면 `onAppear(category:)` 처럼 내용·썸네일을 비운다(격자 내용은 `.loading`). 같은 카테고리면 보관한 썸네일을 둔다.
  /// 지난 격자 Task 의 늦은 결과가 내용을 바꾸지 않게 진입 번호를 올린다. 끝나도 아무것도 하지 않는다.
  public func thumbnailScreenAppeared(category: ImageCategory) async {
    await self.thumbnailScreenAppeared(scope: .category(category))
  }

  /// 검색 결과 화면은 `.search` 로 빌린다. 카테고리와 검색 사이를 오가면 서로의 내용·썸네일을 비운다.
  public func thumbnailScreenAppeared(scope: ThumbnailScope) async {
    self.generation += 1
    if self.thumbnailScope != scope {
      self.switchScope(to: scope)
    }
    await self.waitUntilCancelled()
  }

  /// 칸이 보일 때 썸네일을 읽고, 칸이 보이는 동안(Task 가 취소될 때까지) 기다린다. 끝나면 자기 요청일 때만,
  /// 읽은 썸네일은 최근 `retainedThumbnailLimit` 장 보관 목록에 넣고 읽지 못한 칸은 지운다(다시 보이면 다시 시도한다).
  /// 읽는 중에 사라지면 읽기를 취소하고 지운다. 이미 결과가 있으면(보관분 포함) 다시 읽지 않는다.
  /// 지난 카테고리 격자의 칸이면 아무것도 하지 않는다.
  public func thumbnailAppeared(id: ImageAsset.ID, in category: ImageCategory) async {
    await self.thumbnailAppeared(id: id, scope: .category(category))
  }

  public func thumbnailAppeared(id: ImageAsset.ID, scope: ThumbnailScope) async {
    guard scope == self.thumbnailScope else { return }
    self.thumbnailRequestCount += 1
    let request = self.thumbnailRequestCount
    self.thumbnailOwners[id, default: []].insert(request)
    // 다시 보였다. 보관 목록에서 빼고 주인이 된다.
    self.retainedThumbnailIDs.removeAll { $0 == id }
    if self.thumbnails[id]?.isLoading ?? true {
      self.thumbnails[id] = .loading
      guard let state = await self.loadState(id: id, size: .thumbnail) else {
        // 읽는 중에 칸이 사라졌다.
        self.releaseThumbnail(id: id, request: request)
        return
      }
      guard self.thumbnailOwners[id]?.contains(request) == true else { return }
      // 같은 이미지의 다른 칸이 먼저 읽어 둔 썸네일은 덮지 않는다.
      if case .loaded = self.thumbnails[id] {} else {
        self.thumbnails[id] = state
      }
    }
    await self.waitUntilCancelled()
    self.releaseThumbnail(id: id, request: request)
  }

  /// 상세를 기기에 있는 가장 큰 버전으로 읽고, 닫힐 때까지(Task 가 취소될 때까지) 기다렸다가 자기 요청일 때만 이미지를 놓는다.
  public func detailAppeared(id: ImageAsset.ID) async {
    self.detailRequestCount += 1
    let request = self.detailRequestCount
    self.detail = PhotoDetail(id: id, state: .loading)
    guard let state = await self.loadState(id: id, size: .largestAvailable) else {
      // 읽는 중에 닫혔다.
      self.clearDetail(request: request)
      return
    }
    guard request == self.detailRequestCount else { return }
    self.detail = PhotoDetail(id: id, state: state)
    await self.waitUntilCancelled()
    self.clearDetail(request: request)
  }

  // MARK: - Private

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 다시 읽기에 실패하면 지난 섹션을 둔다(저장소 문제는 보관함 화면의 인덱싱 멈춤 안내가 알린다).
  private func reload(_ category: ImageCategory, photoStore: any PhotoStoreClient, generation: Int) async {
    let items: CategoryItems
    let groupings = CaptureGrouping.groupings(for: category)
    do throws(PhotoStoreError) {
      if groupings.isEmpty {
        items = try await .assets(photoStore.assets(in: category))
      } else {
        items = try await .captureGroups(photoStore.captureGroupItems(in: category), groupings)
      }
    } catch {
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      if case .loaded = self.content {
        return
      }
      self.content = .failed
      return
    }
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    let revision = self.contentRevision
    let current: CategorySections? = if case let .loaded(sections) = self.content {
      sections
    } else {
      nil
    }
    // 1만 장이면 정렬·달력 계산·비교가 진행률마다 되풀이되므로 메인 밖에서 한다. 계산은 취소되지 않아, 돌아온 뒤 같은 규칙으로 버린다.
    let result = await self.sectioning(items, self.calendar, current)
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    // 진행률 대부분은 다른 카테고리만 바꾸므로, 같으면 대입하지 않아 다시 그리지 않는다.
    // 계산하는 동안 내용이 바뀌었으면 비교 결과를 쓰지 않고 대입한다.
    if result.isUnchanged, revision == self.contentRevision {
      return
    }
    self.content = .loaded(result.sections)
  }

  /// 취소되면 nil 이다. 받는 쪽은 결과를 남기지 않는다.
  private func loadState(id: ImageAsset.ID, size: ImageSize) async -> ImageLoadState? {
    do throws(ImageLoadError) {
      return try await .loaded(self.photoLibrary.loadImage(id: id, size: size))
    } catch {
      switch error {
      case .cancelled: return nil
      case .notAvailableLocally: return .unavailable(.inCloudOnly)
      case .notFound: return .unavailable(.notFound)
      case .failed: return .unavailable(.failed)
      }
    }
  }

  /// 다른 화면의 지난 내용과 썸네일이 비치지 않게 비운다. 지난 칸의 Task 는 주인 번호를 찾지 못해 아무것도 하지 않는다.
  private func switchScope(to scope: ThumbnailScope) {
    self.thumbnailScope = scope
    self.content = .loading
    self.thumbnails = [:]
    self.thumbnailOwners = [:]
    self.retainedThumbnailIDs = []
  }

  /// 칸의 Task 가 끝났거나 읽는 중 사라졌다. 같은 이미지의 다른 칸이 남아 있으면 그 칸이 쓰도록 둔다(읽는 중이면 그 칸이 이어 쓴다).
  /// 마지막 칸이면 읽은 썸네일은 보관 목록 끝에 넣고 상한을 넘으면 오래된 것부터 놓고, 읽지 못했거나 읽는 중이던 칸은 지운다.
  /// 보관 목록에는 주인 있는 칸이 없으므로 보이는 칸은 지우지 않는다.
  private func releaseThumbnail(id: ImageAsset.ID, request: Int) {
    guard self.thumbnailOwners[id]?.contains(request) == true else { return }
    self.thumbnailOwners[id]?.remove(request)
    guard self.thumbnailOwners[id]?.isEmpty == true else { return }
    self.thumbnailOwners[id] = nil
    guard case .loaded = self.thumbnails[id] else {
      self.thumbnails[id] = nil
      return
    }
    self.retainedThumbnailIDs.append(id)
    while self.retainedThumbnailIDs.count > Self.retainedThumbnailLimit {
      let oldest = self.retainedThumbnailIDs.removeFirst()
      self.thumbnails[oldest] = nil
    }
  }

  private func clearDetail(request: Int) {
    guard request == self.detailRequestCount else { return }
    self.detail = nil
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }

  /// 부른 Task 가 취소될 때까지 기다린다. 칸·상세가 보이는 동안(View 의 `.task` 수명) 상태를 들고 있다가 사라지면 정리하는 데 쓴다.
  private func waitUntilCancelled() async {
    while !Task.isCancelled {
      // 취소되면 바로 깨어난다.
      try? await Task.sleep(for: .seconds(3600))
    }
  }
}
