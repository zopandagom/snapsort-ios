import Core
import Foundation
import Observation
import PhotoLibraryInterface

/// 사진 상세 페이저(지금 장 ± 1 의 큰 이미지 창)와 상세에서 돌아올 위치(docs/ARCHITECTURE.md §4 카테고리 화면).
/// `CategoryModel` 이 소유하고 상세 이벤트를 넘긴다. 이 타입으로 나눈 것은 CategoryModel 파일 길이 때문이다.
/// 상세 수명의 기다림(닫힐 때까지)은 `CategoryModel` 이 하고, 여기서는 시작(`begin`)과 끝(`end`)만 받는다.
@MainActor
@Observable
final class CategoryDetailPager {
  /// `CategoryModel.detailImages` 가 넘겨 보이는 값.
  private(set) var detailImages: [ImageAsset.ID: ImageLoadState] = [:]
  /// `CategoryModel.detailReturn` 이 넘겨 보이는 값.
  private(set) var detailReturn: PhotoDetailReturn?

  /// 상세 수명을 시작할 때마다 하나씩 올린다. 닫은 뒤 바로 다른(또는 같은) 상세를 열어도 지난 수명의 정리가 지금 상세를 바꾸지 않게 한다.
  @ObservationIgnored private var detailSession = 0
  /// 지금 열린 상세 수명의 번호. 수명 동안만 값이 있다.
  @ObservationIgnored private var activeDetailSession: Int?
  /// 열린 상세의 섹션 스냅숏 식별자와 지금 장 위치.
  @ObservationIgnored private var detailIDs: [ImageAsset.ID] = []
  @ObservationIgnored private var detailIndex = 0
  /// 이 수명의 연 곳. 다음 수명 시작까지 둔다.
  @ObservationIgnored private var detailOrigin: PhotoDetailOrigin?
  /// 읽는 중인 큰 이미지. 창 밖으로 나가거나 닫히면 Task 를 취소하고 뺀다.
  @ObservationIgnored private var detailLoads: [ImageAsset.ID: DetailLoad] = [:]
  /// 큰 이미지 읽기를 시작할 때마다 오른다. 같은 식별자를 다시 읽을 때 지난 읽기의 늦은 결과·정리가 지금 읽기를 바꾸지 않게 한다.
  @ObservationIgnored private var detailLoadCount = 0

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient

  /// - Parameter photoLibrary: 사진 보관함. 큰 이미지를 읽는다.
  init(photoLibrary: any PhotoLibraryClient) {
    self.photoLibrary = photoLibrary
  }

  /// 상세 수명 시작. 위치가 범위 밖이면 nil 이고 아무것도 하지 않는다. 지난 수명의 남은 읽기·이미지를 버리고,
  /// 돌아올 위치를 연 곳·누른 장으로 덮고(연 곳이 nil 이면 nil), 지금 장부터 읽는다. 돌려준 수명 번호를 `end(session:)` 에 넘긴다.
  func begin(ids: [ImageAsset.ID], index: Int, origin: PhotoDetailOrigin?) -> Int? {
    guard ids.indices.contains(index) else { return nil }
    self.detailSession += 1
    let session = self.detailSession
    self.releaseDetailImages()
    self.activeDetailSession = session
    self.detailIDs = ids
    self.detailIndex = index
    self.detailOrigin = origin
    self.detailReturn = origin.map { PhotoDetailReturn(origin: $0, id: ids[index]) }
    self.applyDetailWindow()
    return session
  }

  /// 상세가 닫혔다. 그사이 새 상세가 시작했으면 그 상세의 것이라 건드리지 않는다. 돌아올 위치는 두어,
  /// 원래 화면이 수명 끝보다 먼저든 나중이든 같은 값을 읽게 한다.
  func end(session: Int) {
    guard self.activeDetailSession == session else { return }
    self.releaseDetailImages()
    self.activeDetailSession = nil
    self.detailIDs = []
  }

  /// 지금 장이 바뀌었다(넘김·접근성 동작). 상세가 열려 있지 않거나, 위치가 범위 밖이거나, 그 위치의 식별자가 `id` 가 아니면
  /// (다른 스냅숏의 상세가 보낸 늦은 이벤트) 무시한다. 받아들이면 창을 옮기고, 이 수명에 연 곳이 있으면 돌아올 위치를 이 장으로 바꾼다.
  func pageChanged(index: Int, id: ImageAsset.ID) {
    guard self.activeDetailSession != nil, self.detailIDs.indices.contains(index), self.detailIDs[index] == id
    else { return }
    self.detailIndex = index
    if let origin = self.detailOrigin {
      let target = PhotoDetailReturn(origin: origin, id: id)
      if self.detailReturn != target {
        self.detailReturn = target
      }
    }
    self.applyDetailWindow()
  }

  /// 원래 화면이 돌아올 위치를 썼다. 그 방문의 값일 때만 비운다.
  func returnApplied(visit: UUID) {
    guard self.detailReturn?.origin.visit == visit else { return }
    self.detailReturn = nil
  }

  // MARK: - Private

  /// 지금 창: 지금 장과 범위 안의 앞뒤 장. 스냅숏은 한 섹션이라 같은 식별자가 두 번 들지 않는다.
  private var detailWindow: (current: ImageAsset.ID, neighbors: [ImageAsset.ID]) {
    let neighbors = [self.detailIndex - 1, self.detailIndex + 1]
      .filter { self.detailIDs.indices.contains($0) }
      .map { self.detailIDs[$0] }
    return (self.detailIDs[self.detailIndex], neighbors)
  }

  /// 창 밖 이미지를 놓고 읽는 중이면 취소한다. 지금 장이 상태도 읽기도 없으면 읽고, 지금 장이 끝났으면(읽음·볼 수 없음)
  /// 상태도 읽기도 없는 이웃을 읽는다. 지금 장을 읽는 동안 이웃은 기다린다(디코딩이 겹쳐 지금 장이 늦어지지 않게).
  private func applyDetailWindow() {
    guard let session = self.activeDetailSession else { return }
    let (current, neighbors) = self.detailWindow
    let window = Set(neighbors + [current])
    for id in self.detailImages.keys.filter({ !window.contains($0) }) {
      self.detailImages[id] = nil
    }
    for id in self.detailLoads.keys.filter({ !window.contains($0) }) {
      self.detailLoads.removeValue(forKey: id)?.task.cancel()
    }
    if self.detailImages[current] == nil, self.detailLoads[current] == nil {
      self.startDetailLoad(id: current, session: session)
    }
    guard self.detailImages[current] != nil else { return }
    for id in neighbors where self.detailImages[id] == nil && self.detailLoads[id] == nil {
      self.startDetailLoad(id: id, session: session)
    }
  }

  /// 읽기는 상세 수명과 떨어진 Task 로 하고(창이 옮겨 가면 따로 취소한다), 끝나면 자기 읽기이고 아직 창 안일 때만 남긴다.
  private func startDetailLoad(id: ImageAsset.ID, session: Int) {
    self.detailLoadCount += 1
    let request = self.detailLoadCount
    let photoLibrary = self.photoLibrary
    let task = Task { @MainActor in
      let state = await ImageLoadState.load(id: id, size: .largestAvailable, from: photoLibrary)
      self.detailLoadFinished(id: id, state: state, request: request, session: session)
    }
    self.detailLoads[id] = DetailLoad(task: task, request: request)
  }

  /// 값은 같은 수명·같은 읽기이고 창 안일 때만 남기고, 이웃 읽기로 넘어간다.
  /// 이 Model 이 취소한 읽기(창 밖으로 나감·닫힘·새 상세)는 취소 전에 기록을 지웠으므로 첫 가드에서 버린다. 디코딩 중에 취소돼 값이 늦게 와도
  /// 같다(다시 들어왔으면 새 번호라). 그래서 가드를 지난 취소(nil)는 사진 보관함이 스스로 취소한 읽기다. 다시 읽으면 같은 취소가 되풀이될 수 있어
  /// 실패로 두고 이웃 읽기로 넘어간다(창 밖으로 나갔다 오거나 다시 열면 다시 읽는다).
  private func detailLoadFinished(id: ImageAsset.ID, state: ImageLoadState?, request: Int, session: Int) {
    guard self.detailLoads[id]?.request == request else { return }
    self.detailLoads[id] = nil
    guard self.activeDetailSession == session else { return }
    let (current, neighbors) = self.detailWindow
    guard id == current || neighbors.contains(id) else { return }
    self.detailImages[id] = state ?? .unavailable(.failed)
    self.applyDetailWindow()
  }

  /// 읽는 중인 큰 이미지를 모두 취소하고 이미지를 놓는다.
  private func releaseDetailImages() {
    for load in self.detailLoads.values {
      load.task.cancel()
    }
    self.detailLoads = [:]
    if !self.detailImages.isEmpty {
      self.detailImages = [:]
    }
  }
}

/// 읽는 중인 상세 큰 이미지 하나.
private struct DetailLoad {
  let task: Task<Void, Never>
  let request: Int
}
