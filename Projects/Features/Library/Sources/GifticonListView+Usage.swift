import Core

/// 기프티콘 목록의 머무는 줄(사용 여부를 바꾼 뒤 잠깐 옛 탭에 남는 줄) 상태. `GifticonListView` 의 화면 일시 상태다(저장하지 않는다).
/// 줄 버튼·줄 밀기로 쓰기에 성공하면(`GifticonListModel.usageChanges`) 그 줄은 옛 탭에 남아 도장·색 빠짐(사용함으로 옮길 때만)을 보이고,
/// `SnapStamp.settle` 뒤 빠지기 시작해(`exiting`) `SnapStamp.exitDuration` 뒤 옛 탭에서 사라진다(`settled`).
/// 머무는지는 렌더마다 Model 의 줄별 변경에서 파생하므로, 목록 내용과 변경이 같은 턴에 바뀌어 줄이 빠졌다 다시 들어오는 렌더가 없다.
/// 실패하면 `usageChanges` 가 바뀌지 않아 도장·줄 빠짐이 일어나지 않는다.
struct GifticonUsageLingerState: Equatable {
  /// 이 화면이 생길 때의 `usageRevision`. 그 전의 변경은 애니메이션하지 않는다.
  let baselineSequence: Int
  /// 타이머를 건 변경.
  private(set) var scheduledSequences: Set<Int> = []
  /// 빠지는 중인 변경.
  private(set) var exitingSequences: Set<Int> = []
  /// 옛 탭에서 사라진 변경.
  private(set) var settledSequences: Set<Int> = []

  /// 머무는 줄 하나의 모습.
  struct Linger: Equatable {
    /// 바꾸기 전 사용 여부. 이 값으로 옛 탭에 남는다.
    let wasUsed: Bool
    /// 사용함으로 옮겨 도장을 찍는다(미사용으로 되돌릴 때는 도장 없이 빠지기만 한다).
    let isStamped: Bool
    let isExiting: Bool
  }

  /// 그 줄이 지금 머무는 중이면 모습을, 아니면 nil.
  func linger(for id: ImageAsset.ID, changes: [ImageAsset.ID: GifticonUsageChange]) -> Linger? {
    guard let change = changes[id], self.isLingering(change) else { return nil }
    return Linger(
      wasUsed: !change.isUsed,
      isStamped: change.isUsed,
      isExiting: self.exitingSequences.contains(change.sequence)
    )
  }

  /// 화면에 보일 항목. 머무는 줄은 바꾸기 전 사용 여부로 둬 옛 탭·섹션에 남긴다. 탭 개수도 이것으로 세어 줄이 빠진 뒤 숫자가 바뀐다.
  func displayItems(_ items: [GifticonListItem], changes: [ImageAsset.ID: GifticonUsageChange]) -> [GifticonListItem] {
    items.map { item in
      self.linger(for: item.id, changes: changes).map { item.with(isUsed: $0.wasUsed) } ?? item
    }
  }

  /// 아직 타이머를 걸지 않은 이 화면의 새 변경을 표시하고 돌려준다(순서대로).
  mutating func scheduleNew(_ changes: [ImageAsset.ID: GifticonUsageChange]) -> [GifticonUsageChange] {
    let new = changes.values
      .filter { $0.sequence > self.baselineSequence && !self.scheduledSequences.contains($0.sequence) }
      .sorted { $0.sequence < $1.sequence }
    for change in new {
      self.scheduledSequences.insert(change.sequence)
    }
    return new
  }

  mutating func exit(_ sequence: Int) {
    self.exitingSequences.insert(sequence)
  }

  mutating func settle(_ sequence: Int) {
    self.settledSequences.insert(sequence)
  }

  private func isLingering(_ change: GifticonUsageChange) -> Bool {
    change.sequence > self.baselineSequence && !self.settledSequences.contains(change.sequence)
  }
}
