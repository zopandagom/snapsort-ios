import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 정리 화면의 읽기·후보·선택. 삭제는 `CleanupModelDeletionTests`.
@MainActor
struct CleanupModelTests {
  @Test("열면 읽는 동안 불러오는 중이고, 읽으면 만료됨(최근 만료순)과 사용함 후보를 담고 확인 중은 세기만 한다")
  func loadsCandidates() async {
    let gates = CallGates(holding: [0])
    let model = CleanupFixture.model(photoStore: CleanupFixture.store(onGifticons: { await gates.pass($0) }))

    let appear = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.content == .loading)

    gates.open(0)
    await waitUntil { model.content != .loading }
    #expect(model.content.ids(.expiredGifticons) == ["expired", "estimated"])
    #expect(model.content.ids(.usedGifticons) == ["used"])
    #expect(model.content.sections?.checkingGifticonCount == 1)

    await cancelAndWait(appear)
  }

  @Test("오늘 만료·내일 만료는 후보가 아니다")
  func boundaryGifticonsAreNotCandidates() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    #expect(model.content.candidateIDs == ["expired", "estimated", "used"])

    await cancelAndWait(appear)
  }

  @Test("기본 선택은 규칙으로 읽은 만료 후보와 사용함이고, 추정 만료일은 해제다")
  func selectsDefaults() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    #expect(model.selectedIDs == ["expired", "used"])
    #expect(model.selectionCount == 2)
    let assets: [ImageAsset] = [.stub(id: "expired"), .stub(id: "used")]
    #expect(model.selectionBytes == CleanupSizeEstimate.bytes(of: assets))

    await cancelAndWait(appear)
  }

  @Test("후보를 누르면 골랐다 풀고, 목록에 없는 식별자는 무시한다")
  func togglesCandidates() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    model.candidateToggled(id: "estimated")
    #expect(model.selectedIDs == ["expired", "used", "estimated"])
    model.candidateToggled(id: "estimated")
    model.candidateToggled(id: "used")
    #expect(model.selectedIDs == ["expired"])
    model.candidateToggled(id: "soon")
    #expect(model.selectedIDs == ["expired"])

    await cancelAndWait(appear)
  }

  @Test("섹션 선택은 모두 골라져 있으면 모두 풀고, 아니면 모두 고른다")
  func togglesSection() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    model.sectionSelectionToggled(.expiredGifticons)
    #expect(model.selectedIDs == ["expired", "estimated", "used"])
    model.sectionSelectionToggled(.expiredGifticons)
    #expect(model.selectedIDs == ["used"])
    model.sectionSelectionToggled(.usedGifticons)
    #expect(model.selectedIDs.isEmpty)

    await cancelAndWait(appear)
  }

  @Test("다시 읽을 때 사라진 후보는 선택에서 빠지고, 새로 나타난 만료 후보는 선택하지 않고, 푼 후보는 풀린 채 둔다")
  func reloadKeepsSelectionRules() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()
    model.candidateToggled(id: "used")

    try await photoStore.delete(ids: ["expired"])
    try await photoStore.save([.gifticon(id: "late", expiryDate: .date(2026, 10, 1))])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("late") == true }

    #expect(model.content.candidateIDs == ["late", "estimated", "used"])
    #expect(model.selectedIDs.isEmpty)

    await cancelAndWait(appear)
  }

  @Test("같은 방문으로 다시 열면 선택을 두고 지난 목록을 둔 채 읽고, 새 방문이면 선택을 기본으로 되돌린다")
  func reopenKeepsSelectionOnlyInSameVisit() async {
    let gates = CallGates(holding: [1])
    let model = CleanupFixture.model(photoStore: CleanupFixture.store(onGifticons: { await gates.pass($0) }))
    let visit = UUID()
    let first = await model.open(visit: visit)
    model.candidateToggled(id: "estimated")
    model.candidateToggled(id: "used")
    await cancelAndWait(first)

    let second = Task { await model.onAppear(visit: visit) }
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content != .loading)
    #expect(model.selectedIDs == ["expired", "estimated"])
    gates.open(1)
    await cancelAndWait(second)

    let third = await model.open()
    #expect(model.selectedIDs == ["expired", "used"])

    await cancelAndWait(third)
  }

  @Test("처음 읽기에 실패하면 실패이고, 다시 시도하면 불러오는 중을 거쳐 목록이 보인다")
  func retryAfterFailure() async {
    let gates = CallGates(holding: [1])
    let model = CleanupFixture.model(photoStore: CleanupFixture.store(
      gifticonsErrors: [0: .failed],
      onGifticons: { await gates.pass($0) }
    ))
    let appear = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    #expect(model.content == .loading)
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    await waitUntil { model.content.candidateIDs != nil }
    #expect(model.selectedIDs == ["expired", "used"])

    await cancelAndWait(appear)
  }

  @Test("다시 읽기에 실패하면 지난 목록을 둔다")
  func reloadFailureKeepsList() async {
    let gates = CallGates(holding: [2])
    let photoStore = CleanupFixture.store(gifticonsErrors: [1: .failed], onGifticons: { await gates.pass($0) })
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()

    model.libraryStoreChanged()
    await waitUntil { photoStore.gifticonsCallCount == 2 }
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.content.candidateIDs == ["expired", "estimated", "used"])

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("실패가 아니면 다시 시도는 아무것도 하지 않는다")
  func retryIgnoredUnlessFailed() async {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    let appear = await model.open()
    let content = model.content

    model.retryButtonTapped()
    await settle()

    #expect(model.content == content)
    #expect(photoStore.gifticonsCallCount == 1)

    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 실패이고 삭제 버튼은 무반응이다")
  func missingStoreShowsFailed() async {
    let library = CleanupFixture.library()
    let model = CleanupFixture.model(library: library, photoStore: nil)

    await model.onAppear(visit: UUID())
    await model.deleteButtonTapped()

    #expect(model.content == .failed)
    #expect(library.deletionRequests.isEmpty)
  }

  @Test("날짜가 바뀌어 만료된 기프티콘은 섹션에 들지만 선택하지 않는다")
  func dayChangedAddsExpiredCandidateUnselected() async {
    let clock = CleanupFixture.clock()
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore, clock: clock)
    let appear = await model.open()
    #expect(model.today == .date(2026, 10, 24))

    clock.now = .seoul(2026, 10, 26, hour: 9)
    model.dayChanged()

    #expect(model.today == .date(2026, 10, 26))
    #expect(model.content.ids(.expiredGifticons) == ["soon", "today", "expired", "estimated"])
    #expect(model.selectedIDs == ["expired", "used"])
    #expect(photoStore.gifticonsCallCount == 1)

    await cancelAndWait(appear)
  }

  @Test("화면이 닫혀 있어도 날짜가 바뀌면 오늘을 다시 계산한다")
  func dayChangedWhileClosedUpdatesToday() {
    let clock = CleanupFixture.clock()
    let model = CleanupFixture.model(photoStore: CleanupFixture.store(), clock: clock)

    clock.now = .seoul(2026, 10, 25, hour: 9)
    model.dayChanged()

    #expect(model.today == .date(2026, 10, 25))
  }

  @Test("선택한 것이 없으면 삭제를 요청하지 않는다")
  func deleteWithoutSelectionDoesNothing() async {
    let library = CleanupFixture.library()
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()
    model.sectionSelectionToggled(.expiredGifticons)
    model.sectionSelectionToggled(.expiredGifticons)
    model.sectionSelectionToggled(.usedGifticons)
    #expect(model.selectedIDs.isEmpty)

    await model.deleteButtonTapped()

    #expect(library.deletionRequests.isEmpty)
    #expect(!model.isDeleting)

    await cancelAndWait(appear)
  }

  @Test("화면이 닫혀 있을 때 온 저장소 변경 신호는 저장소를 읽지 않는다")
  func storeChangeWhileClosedIsDropped() async {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.model(photoStore: photoStore)
    model.libraryStoreChanged()
    await settle()
    #expect(photoStore.gifticonsCallCount == 0)

    let appear = await model.open()
    await cancelAndWait(appear)
    model.libraryStoreChanged()
    await settle()

    #expect(photoStore.gifticonsCallCount == 1)
  }

  @Test("안내와 알림 창은 닫으면 사라진다")
  func dismissClearsNoticeAndAlert() async {
    let library = CleanupFixture.library(deletionErrors: [0: .failed])
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    await model.deleteButtonTapped()
    #expect(model.alert == .deleteFailed)
    model.alertDismissed()
    #expect(model.alert == nil)

    await model.deleteButtonTapped()
    #expect(model.notice != nil)
    model.noticeDismissed()
    #expect(model.notice == nil)

    await cancelAndWait(appear)
  }

  @Test("제한 접근이면 알리고, 사진 더 선택은 선택 화면을 띄운 뒤 접근 상태를 다시 읽는다")
  func limitedAccessAndPicker() async {
    let library = CleanupFixture.library(state: .limited)
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    #expect(model.isLimited)

    library.sendIncrementalChange(accessState: .authorized)
    await model.selectMorePhotosTapped()

    #expect(library.limitedPickerPresentCount == 1)
    #expect(!model.isLimited)
  }

  @Test("저장소 변경 신호와 날짜 변경 신호가 접근 상태를 다시 읽는다")
  func signalsRefreshLimitedState() async {
    let library = CleanupFixture.library(state: .limited)
    let model = CleanupFixture.model(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()
    #expect(model.isLimited)

    library.sendIncrementalChange(accessState: .authorized)
    model.libraryStoreChanged()
    await waitUntil { !model.isLimited }

    library.sendIncrementalChange(accessState: .limited)
    model.dayChanged()
    #expect(model.isLimited)

    await cancelAndWait(appear)
  }
}
