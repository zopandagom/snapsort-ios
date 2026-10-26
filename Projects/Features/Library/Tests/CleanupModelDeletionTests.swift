import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 정리 화면의 삭제 흐름: 성공·건너뜀·취소·실패·재진입·화면을 떠난 뒤 결과·재조회와 겹침.
/// 확인 창이 떠 있는 동안은 `deletionGate` 에 `CallGates` 를 걸어 붙잡는다.
@MainActor
struct CleanupModelDeletionTests {
  @Test("삭제하면 고른 것을 요청하고, 지운 후보는 목록과 선택에서 빠지고 안내가 뜬다")
  func deletesSelection() async {
    let library = CleanupFixture.library()
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    await model.deleteButtonTapped()

    #expect(library.deletionRequests == [["expired", "used"]])
    #expect(model.content.candidateIDs == ["estimated"])
    #expect(model.selectedIDs.isEmpty)
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))
    #expect(model.alert == nil)
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("일부가 이미 보관함에 없으면 건너뛰었다고 알리고, 건너뛴 것도 목록에서 뺀다")
  func skippedAreHidden() async {
    let library = CleanupFixture.library(containing: ["expired", "estimated"])
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    await model.deleteButtonTapped()

    #expect(model.notice == CleanupNotice(deletedCount: 1, skippedCount: 1))
    #expect(model.content.candidateIDs == ["estimated"])

    await cancelAndWait(appear)
  }

  @Test("지운 뒤 저장소가 그 행을 아직 돌려줘도 이번 방문에서는 다시 보이지 않는다")
  func deletedStayHiddenWhileStoreLags() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()
    await model.deleteButtonTapped()

    try await photoStore.save([.gifticon(id: "late", expiryDate: .date(2026, 10, 1))])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("late") == true }

    #expect(model.content.candidateIDs == ["late", "estimated"])

    await cancelAndWait(appear)
  }

  @Test("확인 창에서 취소하면 목록·선택·안내 모두 그대로다")
  func cancelledChangesNothing() async {
    let library = CleanupFixture.library(deletionErrors: [0: .userCancelled])
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()
    let content = model.content

    await model.deleteButtonTapped()

    #expect(library.deletionRequests.count == 1)
    #expect(model.content == content)
    #expect(model.selectedIDs == ["expired", "used"])
    #expect(model.notice == nil)
    #expect(model.alert == nil)
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("권한이 없거나 그 밖의 이유로 실패하면 알림 창을 띄우고 선택을 둔다", arguments: [
    (ImageDeletionError.notAuthorized, CleanupAlert.deleteNotAuthorized),
    (ImageDeletionError.failed, CleanupAlert.deleteFailed),
  ])
  func failureShowsAlert(error: ImageDeletionError, alert: CleanupAlert) async {
    let library = CleanupFixture.library(deletionErrors: [0: error])
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    await model.deleteButtonTapped()

    #expect(model.alert == alert)
    #expect(model.selectedIDs == ["expired", "used"])
    #expect(model.content.candidateIDs == ["expired", "estimated", "used"])
    #expect(model.notice == nil)
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("실패한 뒤 다시 누르면 같은 선택으로 다시 요청해 성공한다")
  func retryAfterFailureSucceeds() async {
    let library = CleanupFixture.library(deletionErrors: [0: .failed])
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    await model.deleteButtonTapped()
    model.alertDismissed()
    await model.deleteButtonTapped()

    #expect(library.deletionRequests == [["expired", "used"], ["expired", "used"]])
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))
    #expect(model.alert == nil)

    await cancelAndWait(appear)
  }

  @Test("지우는 동안 다시 눌러도 요청은 한 번이고, 그동안 후보를 고르고 풀 수는 있다")
  func reentryIsBlocked() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.isDeleting)
    await model.deleteButtonTapped()
    model.candidateToggled(id: "estimated")
    #expect(library.deletionRequests.count == 1)
    #expect(model.selectedIDs == ["expired", "used", "estimated"])

    gates.open(0)
    await first.value

    #expect(library.deletionRequests == [["expired", "used"]])
    #expect(!model.isDeleting)
    #expect(model.selectedIDs == ["estimated"])
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))

    await cancelAndWait(appear)
  }

  @Test("화면을 떠나 새로 연 뒤 도착한 결과는 안내를 띄우지 않고, 지운 후보를 새 방문의 목록·선택에서 뺀다")
  func resultAfterNewVisitHidesDeleted() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()
    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(appear)

    let reopened = await model.open()
    gates.open(0)
    await first.value

    #expect(!model.isDeleting)
    #expect(model.notice == nil)
    #expect(model.alert == nil)
    // 저장소가 아직 행을 돌려줘도(인덱서 반영 전) 새 방문 첫 읽기의 기본 선택에서 지운 것이 빠진다.
    #expect(model.selectedIDs.isEmpty)
    #expect(model.content.candidateIDs == ["estimated"])

    await cancelAndWait(reopened)
  }

  @Test("떠난 뒤 도착한 실패도 새 방문에 알림 창을 띄우지 않는다")
  func failureAfterNewVisitIsDropped() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(
      deletionErrors: [0: .failed],
      deletionGate: { _ in await gates.pass(counter.next()) }
    )
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()
    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(appear)

    let reopened = await model.open()
    gates.open(0)
    await first.value

    #expect(model.alert == nil)
    #expect(!model.isDeleting)

    await cancelAndWait(reopened)
  }

  @Test("지우는 중 다시 읽어 후보가 사라지면 선택에서도 빠지고, 결과가 와도 다시 생기지 않는다")
  func vanishedCandidateLeavesSelectionWhileDeleting() async throws {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let photoStore = CleanupFixture.store()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let model = CleanupFixture.model(library: library, photoStore: photoStore)
    let appear = await model.open()
    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }

    try await photoStore.delete(ids: ["expired"])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("expired") == false }
    #expect(model.selectedIDs == ["used"])

    gates.open(0)
    await first.value

    #expect(model.selectedIDs.isEmpty)
    #expect(model.content.candidateIDs == ["estimated"])

    await cancelAndWait(appear)
  }

  @Test("지운 뒤 저장소가 행을 돌려주는 동안 새 방문에서는 후보로 보이되 선택하지 않고, 행이 사라진 뒤 다시 생기면 선택한다")
  func recentlyDeletedAreNotSelectedInNextVisit() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let first = await model.open()
    await model.deleteButtonTapped()
    await cancelAndWait(first)

    let second = await model.open()
    #expect(model.content.candidateIDs == ["expired", "estimated", "used"])
    #expect(model.selectedIDs.isEmpty)

    // 인덱서가 행을 지웠다.
    try await photoStore.delete(ids: ["expired", "used"])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs == ["estimated"] }
    await cancelAndWait(second)

    // 같은 식별자가 다시 들어온다(복구).
    try await photoStore.save([.gifticon(id: "expired", expiryDate: .date(2026, 10, 23))])
    let third = await model.open()
    #expect(model.content.candidateIDs?.contains("expired") == true)
    #expect(model.selectedIDs == ["expired"])

    await cancelAndWait(third)
  }

  @Test("떠난 뒤 도착한 성공 결과도 지운 식별자는 다음 방문의 기본 선택에서 뺀다")
  func resultAfterNewVisitStillMarksRecentlyDeleted() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()
    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(appear)
    gates.open(0)
    await first.value

    let reopened = await model.open()

    #expect(model.content.candidateIDs == ["expired", "estimated", "used"])
    #expect(model.selectedIDs.isEmpty)

    await cancelAndWait(reopened)
  }
}
