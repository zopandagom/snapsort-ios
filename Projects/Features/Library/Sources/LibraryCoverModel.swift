import Core
import Foundation
import Observation
import PhotoLibraryInterface

/// 보관함 화면 카드의 대표 썸네일과 곧 만료 띠 칩 썸네일의 상태와 로직 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 대표 식별자는 `LibraryModel.coverIDs` 가 개수와 같은 세대로 갖고, LibraryView 가 바뀔 때마다 `coversChanged(_:)` 로 넘긴다.
/// 띠 칩 식별자는 `LibraryModel.expiringThumbnailIDs` 이고 `expiringChanged(_:)` 로 넘긴다
/// (Model 끼리 참조하지 않는다, docs/ARCHITECTURE.md §1 규칙 6).
/// 썸네일은 지금 대표 집합 ∪ 띠 칩 집합(보관 집합) 안의 것만 보관한다. 카테고리 화면(`CategoryModel`)의 썸네일과 상태를 나눠 가져
/// 카테고리·검색·정리 화면 전환이 이 썸네일을 놓지 않고, 그 반대도 없다(같은 사진이 두 Model 에 따로 있을 수 있다).
/// 읽기는 카드의 `.task` 가 아니라 보관함 NavigationStack 의 `.task` 수명인 로더(`onAppear()`)가 해서,
/// 화면을 push 해 카드가 사라져도 읽는 중인 것과 읽은 것을 잃지 않고, push 동안 바뀐 대표도 돌아오기 전에 채운다.
/// App 이 소유해 보관함 화면에 다시 들어와도(온보딩·기록 도구에서) 읽은 썸네일이 남는다.
@MainActor
@Observable
public final class LibraryCoverModel {
  /// 대표 썸네일. `.loaded` 또는 `.unavailable` 만 담는다. 없으면 아직 안 읽었거나 읽는 중이다(화면은 같은 중립 면).
  /// 키는 늘 지금 보관 집합 안이라 최대 68장(대표: 카테고리 12 × `LibraryModel.coverLimit` = 48, 띠: `LibraryModel.expiringLimit` = 20.
  /// 4:3 사진 약 54MB, 최대 약 68MB)이다. 대표와 띠에 같은 사진이 있으면 한 장이다.
  public private(set) var thumbnails: [ImageAsset.ID: ImageLoadState] = [:]

  /// 지금 대표 집합.
  @ObservationIgnored private var coverIDs: Set<ImageAsset.ID> = []
  /// 지금 곧 만료 띠 칩 집합.
  @ObservationIgnored private var expiringIDs: Set<ImageAsset.ID> = []
  /// 보관 집합(대표 ∪ 띠 칩). 이 밖의 식별자는 어떤 이벤트에서도 읽거나 보관하지 않는다.
  private var retainedIDs: Set<ImageAsset.ID> {
    self.coverIDs.union(self.expiringIDs)
  }

  /// 읽는 중인 식별자 → 요청 번호. 보관 집합에서 빠졌거나, 다시 요청됐거나, 새 로더가 시작돼 번호가 맞지 않는 늦은 결과는 버린다.
  /// 로더가 취소된 뒤 결과를 받지 못한 요청은 여기 남지만(로더가 끝나 통로가 닫히기 전 짧은 창에서 든 요청도 같다),
  /// 다음 로더 시작(`onAppear()`)이 비우고 상태 없는 보관 집합 칸을 다시 요청하므로 그대로 둔다.
  @ObservationIgnored private var loading: [ImageAsset.ID: Int] = [:]
  @ObservationIgnored private var requestCount = 0
  /// 읽기 요청 통로. 로더(`onAppear()`)가 도는 동안만 있다.
  @ObservationIgnored private var loadRequests: AsyncStream<CoverLoad>.Continuation?
  /// `onAppear()` 를 시작할 때마다 하나씩 올린다. 지난 로더가 늦게 끝나도 새 로더의 통로를 지우지 않게 한다.
  @ObservationIgnored private var loaderGeneration = 0

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  /// - Parameter photoLibrary: 대표 썸네일을 읽는 사진 보관함.
  public init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
  }

  // MARK: - Events

  /// 썸네일 로더. 보관함 화면 NavigationStack 의 `.task` 수명 동안 읽기 요청을 받아 읽는다.
  /// 시작할 때 보관 집합 중 아직 상태가 없는 것(로더보다 대표·띠 칩이 먼저 왔거나, 지난 로더가 취소돼 못 읽은 것)을 요청한다.
  public func onAppear() async {
    self.loaderGeneration += 1
    let generation = self.loaderGeneration
    // 요청은 대표 집합 크기로 묶이므로 버리지 않는다.
    let (requests, continuation) = AsyncStream.makeStream(of: CoverLoad.self)
    self.loadRequests = continuation
    // 지난 로더의 읽기는 취소됐다. 늦게 와도 번호가 맞지 않아 버려진다.
    self.loading = [:]
    for id in self.retainedIDs where self.thumbnails[id] == nil {
      self.request(id)
    }
    await withDiscardingTaskGroup { group in
      for await load in requests {
        group.addTask { await self.load(load) }
      }
    }
    // 화면이 사라졌다. 이후 요청은 버리고, 다음 진입이 상태 없는 칸을 다시 요청한다.
    if generation == self.loaderGeneration {
      self.loadRequests = nil
    }
  }

  /// 대표 집합이 바뀌었다(`LibraryModel.coverIDs`). 빠진 썸네일을 놓고, 아직 상태가 없는 대표를 카드 이벤트 없이 바로 요청한다.
  /// 대체 상태(`.unavailable`)는 여기서 다시 읽지 않는다(진행률마다 iCloud 에만 있는 사진을 다시 요청하지 않게). 카드가 다시 보일 때 읽는다.
  /// 띠 칩에 남아 있는 사진은 놓지 않는다.
  public func coversChanged(_ covers: [ImageCategory: [ImageAsset.ID]]) {
    self.coverIDs = Set(covers.values.joined())
    self.retainedIDsChanged()
  }

  /// 곧 만료 띠 칩 집합이 바뀌었다(`LibraryModel.expiringThumbnailIDs`). `coversChanged(_:)` 와 같다: 빠진 썸네일을 놓고(대표에 남아 있으면 둔다),
  /// 상태 없는 칩을 바로 요청하고, 대체 상태는 다시 읽지 않는다(칩이 다시 보일 때 `cardAppeared(ids:)` 로 읽는다).
  public func expiringChanged(_ ids: [ImageAsset.ID]) {
    self.expiringIDs = Set(ids)
    self.retainedIDsChanged()
  }

  /// 카드나 띠 칩이 보였다. 보관 집합 중 대체 상태인 칸만 다시 읽고, 읽는 동안 대체 상태를 그대로 둔다(대체 → 중립 → 대체로 깜빡이지 않게).
  /// 보관 집합 밖 식별자·읽은 칸·상태 없는 칸(이미 `coversChanged(_:)`·`expiringChanged(_:)`·`onAppear()` 가 요청함)은 무시한다.
  public func cardAppeared(ids: [ImageAsset.ID]) {
    let retainedIDs = self.retainedIDs
    for id in ids where retainedIDs.contains(id) {
      if case .unavailable = self.thumbnails[id] {
        self.request(id)
      }
    }
  }

  // MARK: - Private

  /// 보관 집합 밖 썸네일·읽기를 놓고, 상태 없는 칸을 요청한다.
  private func retainedIDsChanged() {
    let retainedIDs = self.retainedIDs
    let kept = self.thumbnails.filter { retainedIDs.contains($0.key) }
    if kept.count != self.thumbnails.count {
      self.thumbnails = kept
    }
    self.loading = self.loading.filter { retainedIDs.contains($0.key) }
    for id in retainedIDs where self.thumbnails[id] == nil {
      self.request(id)
    }
  }

  /// 로더가 없거나 이미 읽는 중이면 아무것도 하지 않는다. 같은 이미지가 두 카드(또는 카드와 띠)에 있어도 한 번만 읽는다.
  private func request(_ id: ImageAsset.ID) {
    guard let loadRequests = self.loadRequests, self.loading[id] == nil else { return }
    self.requestCount += 1
    self.loading[id] = self.requestCount
    loadRequests.yield(CoverLoad(id: id, request: self.requestCount))
  }

  /// 요청 번호가 맞을 때만 결과를 남긴다. 취소되면(로더가 끝남) 상태를 바꾸지 않아 다음 진입이 다시 요청한다.
  private func load(_ load: CoverLoad) async {
    let state = await ImageLoadState.load(id: load.id, size: .thumbnail, from: self.photoLibrary)
    guard self.loading[load.id] == load.request else { return }
    self.loading[load.id] = nil
    guard let state else { return }
    self.thumbnails[load.id] = state
  }
}

/// 로더에 넘기는 썸네일 읽기 요청 하나.
struct CoverLoad: Sendable {
  let id: ImageAsset.ID
  let request: Int
}
