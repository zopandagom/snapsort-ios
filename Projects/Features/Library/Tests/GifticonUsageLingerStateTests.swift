import Core
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 기프티콘 목록의 머무는 줄 상태(`GifticonUsageLingerState`): 기준 이전 변경 무시, 옛 탭에 머문 뒤 빠짐, 같은 줄의 새 변경 대체.
struct GifticonUsageLingerStateTests {
  private static func item(_ id: String, isUsed: Bool) -> GifticonListItem {
    GifticonListItem(asset: .stub(id: id), status: .checking, isUsed: isUsed)
  }

  private static func change(_ id: String, isUsed: Bool, sequence: Int) -> GifticonUsageChange {
    GifticonUsageChange(id: id, isUsed: isUsed, sequence: sequence)
  }

  @Test("화면이 생기기 전(기준 번호 이하)의 변경은 타이머를 걸지 않고 머물지도 않는다")
  func ignoresChangesAtOrBeforeBaseline() {
    var state = GifticonUsageLingerState(baselineSequence: 2)
    let changes = ["a": Self.change("a", isUsed: true, sequence: 2)]

    #expect(state.scheduleNew(changes).isEmpty)
    #expect(state.linger(for: "a", changes: changes) == nil)
    #expect(state.displayItems([Self.item("a", isUsed: true)], changes: changes) == [Self.item("a", isUsed: true)])
  }

  @Test("새 변경은 한 번만, 번호 순서대로 돌려준다")
  func schedulesNewChangesOnceInOrder() {
    var state = GifticonUsageLingerState(baselineSequence: 0)
    let changes = [
      "b": Self.change("b", isUsed: true, sequence: 2),
      "a": Self.change("a", isUsed: false, sequence: 1),
    ]

    #expect(state.scheduleNew(changes).map(\.sequence) == [1, 2])
    #expect(state.scheduleNew(changes).isEmpty)
  }

  @Test("사용함으로 옮긴 줄은 옛 탭(미사용)에 도장과 함께 머물다 빠지고, settle 뒤 새 탭(사용함)으로 간다")
  func lingersInOldTabUntilSettled() {
    var state = GifticonUsageLingerState(baselineSequence: 0)
    let changes = ["a": Self.change("a", isUsed: true, sequence: 1)]
    let items = [Self.item("a", isUsed: true)]
    _ = state.scheduleNew(changes)

    #expect(state.linger(for: "a", changes: changes) == .init(wasUsed: false, isStamped: true, isExiting: false))
    #expect(state.displayItems(items, changes: changes).map(\.isUsed) == [false])

    state.exit(1)
    #expect(state.linger(for: "a", changes: changes)?.isExiting == true)
    #expect(state.displayItems(items, changes: changes).map(\.isUsed) == [false])

    state.settle(1)
    #expect(state.linger(for: "a", changes: changes) == nil)
    #expect(state.displayItems(items, changes: changes).map(\.isUsed) == [true])
  }

  @Test("미사용으로 되돌린 줄은 도장 없이 옛 탭(사용함)에 머문다")
  func restoreLingersWithoutStamp() {
    var state = GifticonUsageLingerState(baselineSequence: 0)
    let changes = ["a": Self.change("a", isUsed: false, sequence: 1)]
    _ = state.scheduleNew(changes)

    #expect(state.linger(for: "a", changes: changes) == .init(wasUsed: true, isStamped: false, isExiting: false))
    #expect(state.displayItems([Self.item("a", isUsed: false)], changes: changes).map(\.isUsed) == [true])
  }

  @Test("같은 줄을 다시 밀면 새 번호의 변경이 옛 변경을 대신해, 옛 변경의 빠짐·settle 이 새 변경에 닿지 않는다")
  func newSequenceReplacesOldForSameRow() {
    var state = GifticonUsageLingerState(baselineSequence: 0)
    _ = state.scheduleNew(["a": Self.change("a", isUsed: true, sequence: 1)])
    state.exit(1)
    state.settle(1)

    let changes = ["a": Self.change("a", isUsed: false, sequence: 2)]
    #expect(state.scheduleNew(changes).map(\.sequence) == [2])
    #expect(state.linger(for: "a", changes: changes) == .init(wasUsed: true, isStamped: false, isExiting: false))
    #expect(state.displayItems([Self.item("a", isUsed: false)], changes: changes).map(\.isUsed) == [true])
  }
}
