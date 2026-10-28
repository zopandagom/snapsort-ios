import Core

/// 체크 원 끌기 한 번 (docs/ARCHITECTURE.md §4 정리 도우미 선택). 시작 줄과 방향, 끌기 전 선택을 들고 범위식으로 선택을 셈한다.
/// 시작 줄~지금 줄(화면 순서)에 방향을 주고, 범위 밖은 끌기 전 상태로 둔다. 고르는 끌기는 남길 장을 건너뛰고(시작 줄은 고른다),
/// 푸는 끌기는 남길 장도 푼다(`bulkSelectableIDs` 와 같은 이유: 묶음을 통째로 지우는 실수를 막는다).
struct CleanupDragSelection: Equatable {
  let startID: ImageAsset.ID
  /// 시작 줄이 골라져 있지 않았으면 true(고르는 끌기), 골라져 있었으면 false(푸는 끌기).
  let selects: Bool
  /// 끌기 전 선택. 범위 밖 후보는 이 상태로 돌아간다. 다시 읽으면 보이는 후보로 줄인다.
  private(set) var base: Set<ImageAsset.ID>
  /// 마지막으로 손가락이 있던 후보.
  private(set) var currentID: ImageAsset.ID

  init(startID: ImageAsset.ID, selection: Set<ImageAsset.ID>) {
    self.startID = startID
    self.selects = !selection.contains(startID)
    self.base = selection
    self.currentID = startID
  }

  /// `order`(화면 순서)에서 시작~`id` 범위에 방향을 준 선택. `id` 나 시작이 `order` 에 없으면 nil(아무것도 바꾸지 않는다).
  mutating func selection(movingTo id: ImageAsset.ID, order: [CleanupCandidate]) -> Set<ImageAsset.ID>? {
    guard let start = order.firstIndex(where: { $0.id == self.startID }),
          let end = order.firstIndex(where: { $0.id == id })
    else { return nil }
    var result = self.base
    for candidate in order[min(start, end) ... max(start, end)] {
      if self.selects {
        guard !candidate.isKept || candidate.id == self.startID else { continue }
        result.insert(candidate.id)
      } else {
        result.remove(candidate.id)
      }
    }
    self.currentID = id
    return result
  }

  /// 다시 읽기·삭제 결과로 보이는 후보가 바뀌었다. `base` 를 그 후보로 줄인다.
  mutating func restrict(to candidateIDs: Set<ImageAsset.ID>) {
    self.base.formIntersection(candidateIDs)
  }
}
