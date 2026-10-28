import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 최근 스크린샷 화면의 삭제 흐름: 성공·건너뜀·취소·실패·재진입·화면을 떠난 뒤 결과·재조회와 겹침.
@MainActor
struct CaptureInboxModelDeletionTests {
  /// 첫 두 장을 삭제 표시한 모델.
  private static func markedModel(
    library: PhotoLibraryClientFake,
    photoStore: PhotoStoreClientFake = CleanupFixture.store()
  ) async -> (model: CaptureInboxModel, appear: Task<Void, Never>) {
    let model = CleanupFixture.inboxModel(library: library, photoStore: photoStore)
    let appear = await model.open()
    model.markForDeletionTapped()
    model.markForDeletionTapped()
    return (model, appear)
  }

  @Test("삭제하면 표시한 것을 요청하고, 지운 장은 목록과 표시에서 빠지고 안내가 뜬다")
  func deletesMarked() async {
    let library = CleanupFixture.library()
    let (model, appear) = await Self.markedModel(library: library)

    await model.deleteButtonTapped()

    #expect(library.deletionRequests == [["s1", "s2"]])
    #expect(model.content.ids == ["s3"])
    #expect(model.markedIDs.isEmpty)
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))
    #expect(model.alert == nil)
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("일부가 이미 보관함에 없으면 건너뛰었다고 알리고, 건너뛴 장도 목록에서 뺀다")
  func skippedAreHidden() async {
    let library = CleanupFixture.library(containing: ["s1", "s3"])
    let (model, appear) = await Self.markedModel(library: library)

    await model.deleteButtonTapped()

    #expect(model.notice == CleanupNotice(deletedCount: 1, skippedCount: 1))
    #expect(model.content.ids == ["s3"])

    await cancelAndWait(appear)
  }

  @Test("지운 뒤 저장소가 그 행을 아직 돌려줘도 이번 방문에서는 다시 보이지 않는다")
  func deletedStayHiddenWhileStoreLags() async throws {
    let photoStore = CleanupFixture.store()
    let (model, appear) = await Self.markedModel(library: CleanupFixture.library(), photoStore: photoStore)
    await model.deleteButtonTapped()

    try await photoStore.save([.screenshot(id: "s4", .seoul(2026, 10, 24, hour: 8))])
    model.libraryStoreChanged()
    await waitUntil { model.content.ids?.contains("s4") == true }

    #expect(model.content.ids == ["s4", "s3"])

    await cancelAndWait(appear)
  }

  @Test("확인 창에서 취소하면 목록·표시·안내 모두 그대로다")
  func cancelledChangesNothing() async {
    let library = CleanupFixture.library(deletionErrors: [0: .userCancelled])
    let (model, appear) = await Self.markedModel(library: library)

    await model.deleteButtonTapped()

    #expect(library.deletionRequests.count == 1)
    #expect(model.content.ids == ["s1", "s2", "s3"])
    #expect(model.markedIDs == ["s1", "s2"])
    #expect(model.notice == nil)
    #expect(model.alert == nil)
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("권한이 없거나 그 밖의 이유로 실패하면 알림 창을 띄우고 표시를 둔다", arguments: [
    (ImageDeletionError.notAuthorized, CleanupAlert.deleteNotAuthorized),
    (ImageDeletionError.failed, CleanupAlert.deleteFailed),
  ])
  func failureShowsAlert(error: ImageDeletionError, alert: CleanupAlert) async {
    let library = CleanupFixture.library(deletionErrors: [0: error])
    let (model, appear) = await Self.markedModel(library: library)

    await model.deleteButtonTapped()

    #expect(model.alert == alert)
    #expect(model.markedIDs == ["s1", "s2"])
    #expect(model.content.ids == ["s1", "s2", "s3"])
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("실패한 뒤 안내를 닫고 다시 누르면 같은 표시로 다시 요청해 성공하고, 안내를 닫으면 사라진다")
  func retryAfterFailureSucceeds() async {
    let library = CleanupFixture.library(deletionErrors: [0: .failed])
    let (model, appear) = await Self.markedModel(library: library)

    await model.deleteButtonTapped()
    model.alertDismissed()
    #expect(model.alert == nil)
    await model.deleteButtonTapped()

    #expect(library.deletionRequests == [["s1", "s2"], ["s1", "s2"]])
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))
    model.noticeDismissed()
    #expect(model.notice == nil)

    await cancelAndWait(appear)
  }

  @Test("표시한 것이 없으면 삭제를 요청하지 않는다")
  func deleteWithoutMarksDoesNothing() async {
    let library = CleanupFixture.library()
    let model = CleanupFixture.inboxModel(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    await model.deleteButtonTapped()

    #expect(library.deletionRequests.isEmpty)

    await cancelAndWait(appear)
  }

  @Test("지우는 동안 다시 눌러도 요청은 한 번이고, 보관은 막히고, 표시는 더할 수 있다")
  func reentryIsBlocked() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let photoStore = CleanupFixture.store()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let (model, appear) = await Self.markedModel(library: library, photoStore: photoStore)

    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.isDeleting)
    await model.deleteButtonTapped()
    await model.keepTapped()
    model.markForDeletionTapped()
    #expect(model.markedIDs == ["s1", "s2", "s3"])
    #expect(library.deletionRequests.count == 1)
    #expect(photoStore.keepInCaptureInboxCount == 0)

    gates.open(0)
    await first.value

    #expect(library.deletionRequests == [["s1", "s2"]])
    #expect(!model.isDeleting)
    #expect(model.markedIDs == ["s3"])
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))

    await cancelAndWait(appear)
  }

  @Test("화면을 떠나 새로 연 뒤 도착한 결과는 안내를 띄우지 않고, 지운 장을 새 방문의 목록에서 뺀다")
  func resultAfterNewVisitHidesDeleted() async {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let (model, appear) = await Self.markedModel(library: library)
    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(appear)

    let reopened = await model.open()
    gates.open(0)
    await first.value

    #expect(!model.isDeleting)
    #expect(model.notice == nil)
    #expect(model.alert == nil)
    #expect(model.markedIDs.isEmpty)
    // 저장소가 아직 행을 돌려줘도(인덱서 반영 전) 지운 장이 새 방문의 지금 장으로 보이지 않는다.
    #expect(model.content.ids == ["s3"])
    #expect(model.current?.id == "s3")

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
    let (model, appear) = await Self.markedModel(library: library)
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

  @Test("지우는 중 다시 읽어 장이 사라지면 표시에서도 빠지고, 결과가 와도 다시 생기지 않는다")
  func vanishedImageLeavesMarksWhileDeleting() async throws {
    let gates = CallGates(holding: [0])
    let counter = CallCounter()
    let photoStore = CleanupFixture.store()
    let library = CleanupFixture.library(deletionGate: { _ in await gates.pass(counter.next()) })
    let (model, appear) = await Self.markedModel(library: library, photoStore: photoStore)
    let first = Task { await model.deleteButtonTapped() }
    await waitUntil { gates.hasEntered(0) }

    try await photoStore.delete(ids: ["s2"])
    model.libraryStoreChanged()
    await waitUntil { model.content.ids == ["s1", "s3"] }
    #expect(model.markedIDs == ["s1"])

    gates.open(0)
    await first.value

    #expect(model.markedIDs.isEmpty)
    #expect(model.content.ids == ["s3"])

    await cancelAndWait(appear)
  }
}
