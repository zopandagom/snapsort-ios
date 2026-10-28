import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 정리 화면의 체크 원 끌기와 다시 읽기·삭제·방문의 겹침 (docs/ARCHITECTURE.md §4 정리 도우미 선택).
/// 기본 데이터(`CleanupFixture`)의 화면 순서는 `expired`·`estimated`(만료됨) → `used`(사용함), 기본 선택은 `expired`·`used` 다.
@MainActor
struct CleanupModelDragSelectionOverlapTests {
  @Test("끌기 중 다시 읽기로 사라진 후보는 선택과 끌기 전 상태에서 빠지고, 끌기는 남은 순서로 이어진다")
  func reloadRemovingCandidateDropsItFromRange() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()
    model.dragSelectionBegan(id: "estimated")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    try await photoStore.delete(ids: ["used"])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("used") == false }

    #expect(model.selectedIDs == ["expired", "estimated"])
    #expect(model.isDragSelecting)
    model.dragSelectionMoved(to: "expired")
    #expect(model.selectedIDs == ["expired", "estimated"])
    model.dragSelectionMoved(to: "estimated")
    #expect(model.selectedIDs == ["expired", "estimated"])

    await cancelAndWait(appear)
  }

  @Test("끌기 중 다시 읽기로 시작 줄이 사라지면 끌기가 끝나 그 뒤 이동은 선택을 바꾸지 않는다")
  func reloadRemovingStartEndsDrag() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()
    model.dragSelectionBegan(id: "estimated")

    try await photoStore.delete(ids: ["estimated"])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("estimated") == false }

    #expect(!model.isDragSelecting)
    #expect(model.selectedIDs == ["expired", "used"])
    model.dragSelectionMoved(to: "expired")
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["expired", "used"])

    await cancelAndWait(appear)
  }

  @Test("지우는 동안에도 끌어 고를 수 있고, 결과가 오면 지운 줄이 빠진 채 끌기가 이어진다")
  func dragWorksWhileDeleting() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    let deletion = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.isDeleting)
    model.dragSelectionBegan(id: "estimated")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    gates.open(0)
    await deletion.value

    #expect(library.deletionRequests == [["expired", "used"]])
    #expect(model.selectedIDs == ["estimated"])
    #expect(model.isDragSelecting)

    await cancelAndWait(appear)
  }

  @Test("지우는 동안 시작한 끌기는 시작 줄이 지워지면 끝난다")
  func deletingStartEndsDrag() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    let deletion = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    model.dragSelectionBegan(id: "used")
    #expect(model.selectedIDs == ["expired"])

    gates.open(0)
    await deletion.value

    #expect(model.content.candidateIDs == ["estimated"])
    #expect(!model.isDragSelecting)
    model.dragSelectionMoved(to: "estimated")
    #expect(model.selectedIDs.isEmpty)

    await cancelAndWait(appear)
  }

  @Test("끌기 중 화면이 다시 열리면 같은 방문이든 새 방문이든 지난 끌기를 버린다")
  func reopeningDiscardsDrag() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let visit = UUID()
    let first = await model.open(visit: visit)
    model.dragSelectionBegan(id: "estimated")

    // 사진 상세에서 돌아옴(같은 방문). 내용이 이미 있어 `open` 이 기다리지 않으므로 끌기가 버려지기를 기다린다.
    let second = Task { await model.onAppear(visit: visit) }
    await waitUntil { !model.isDragSelecting }
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    model.dragSelectionBegan(id: "expired")
    let third = await model.open()
    #expect(!model.isDragSelecting)
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["expired", "used"])

    await cancelAndWait(first)
    await cancelAndWait(second)
    await cancelAndWait(third)
  }

  @Test("끌기 중 화면이 닫히면 끌기를 버려, 다시 열어도 이어지지 않는다")
  func closingScreenDiscardsDrag() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let visit = UUID()
    let first = await model.open(visit: visit)
    model.dragSelectionBegan(id: "estimated")

    await cancelAndWait(first)
    #expect(!model.isDragSelecting)

    let second = await model.open(visit: visit)
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])
    model.dragSelectionMoved(to: "expired")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    await cancelAndWait(second)
  }
}
