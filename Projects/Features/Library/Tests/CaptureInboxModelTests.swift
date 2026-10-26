import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 캡처 인박스의 읽기·보관·삭제 표시. 읽기 조건(스크린샷·기간·보관 안 함)은 저장소가 맡아 PhotoStore 테스트가 본다.
@MainActor
struct CaptureInboxModelTests {
  private static func screenshots(_ ids: String...) -> [ImageAsset] {
    ids.map { .stub(id: $0, isScreenshot: true) }
  }

  @Test("열면 읽는 동안 불러오는 중이고, 읽으면 기간 안 스크린샷을 최신순으로 담고 기간 시작을 저장소에 넘긴다")
  func loadsRecentScreenshots() async {
    let gates = CallGates(holding: [0])
    let photoStore = CleanupFixture.store(onCaptureInboxScreenshots: { await gates.pass($0) })
    let model = CleanupFixture.inboxModel(photoStore: photoStore)

    let appear = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.content == .loading)

    gates.open(0)
    await waitUntil { model.content != .loading }
    #expect(model.content.ids == ["s1", "s2", "s3"])
    #expect(photoStore.captureInboxSinceArguments == [.seoul(2026, 9, 25, hour: 0)])

    await cancelAndWait(appear)
  }

  @Test("대상이 없으면 빈 목록이고 지금 장이 없다")
  func emptyInbox() async {
    let model = CleanupFixture.inboxModel(photoStore: PhotoStoreClientFake())
    let appear = await model.open()

    #expect(model.content == .loaded([]))
    #expect(model.current == nil)
    #expect(model.position == nil)

    await cancelAndWait(appear)
  }

  @Test("지금 장은 삭제 표시하지 않은 첫 장이고, 표시하면 다음 장으로 넘어간다")
  func currentSkipsMarked() async {
    let model = CleanupFixture.inboxModel(photoStore: CleanupFixture.store())
    let appear = await model.open()
    #expect(model.current?.id == "s1")
    #expect(model.position?.index == 1)
    #expect(model.position?.total == 3)

    model.markForDeletionTapped()
    #expect(model.markedIDs == ["s1"])
    #expect(model.current?.id == "s2")
    #expect(model.position?.index == 2)

    model.markForDeletionTapped()
    model.markForDeletionTapped()
    #expect(model.current == nil)
    #expect(model.position == nil)
    model.markForDeletionTapped()
    #expect(model.markedIDs == ["s1", "s2", "s3"])

    await cancelAndWait(appear)
  }

  @Test("표시를 누르면 풀고 없는 식별자는 무시하며, 표시한 것의 확보 용량을 센다")
  func unmarkAndBytes() async {
    let model = CleanupFixture.inboxModel(photoStore: CleanupFixture.store())
    let appear = await model.open()
    model.markForDeletionTapped()
    model.markForDeletionTapped()
    #expect(model.markedBytes == CleanupSizeEstimate.bytes(of: Self.screenshots("s1", "s2")))

    model.unmarkTapped(id: "nope")
    #expect(model.markedIDs == ["s1", "s2"])
    model.unmarkTapped(id: "s1")
    #expect(model.markedIDs == ["s2"])
    #expect(model.current?.id == "s1")
    #expect(model.markedBytes == CleanupSizeEstimate.bytes(of: Self.screenshots("s2")))

    await cancelAndWait(appear)
  }

  @Test("보관하면 저장소에 저장하고 목록에서 빼며, 전체 수는 줄지 않게 센다")
  func keepSavesAndHides() async {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let appear = await model.open()

    await model.keepTapped()

    #expect(photoStore.keptInCaptureInboxIDs == ["s1"])
    #expect(model.content.ids == ["s2", "s3"])
    #expect(model.current?.id == "s2")
    #expect(model.position?.index == 2)
    #expect(model.position?.total == 3)
    #expect(model.keepingID == nil)

    await cancelAndWait(appear)
  }

  @Test("보관 시점에 행이 이미 없으면 그 장도 목록에서 뺀다")
  func keepOfMissingRowHides() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let appear = await model.open()
    try await photoStore.delete(ids: ["s1"])

    await model.keepTapped()

    #expect(photoStore.keepInCaptureInboxCount == 1)
    #expect(model.content.ids == ["s2", "s3"])
    #expect(model.alert == nil)

    await cancelAndWait(appear)
  }

  @Test("보관 저장에 실패하면 알림 창을 띄우고 그 장을 그대로 둔다")
  func keepFailureShowsAlert() async {
    let photoStore = CleanupFixture.store(captureInboxKeepError: .failed)
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let appear = await model.open()

    await model.keepTapped()

    #expect(model.alert == .keepFailed)
    #expect(model.content.ids == ["s1", "s2", "s3"])
    #expect(model.current?.id == "s1")
    #expect(model.keepingID == nil)
    #expect(photoStore.keptInCaptureInboxIDs.isEmpty)

    await cancelAndWait(appear)
  }

  @Test("모두 확인했거나 읽기 전이면 보관·표시는 아무것도 하지 않는다")
  func actionsWithoutCurrentDoNothing() async {
    let photoStore = PhotoStoreClientFake()
    let model = CleanupFixture.inboxModel(photoStore: photoStore)

    await model.keepTapped()
    model.markForDeletionTapped()

    #expect(model.markedIDs.isEmpty)
    #expect(photoStore.keepInCaptureInboxCount == 0)
  }

  @Test("새 방문이면 삭제 표시를 버리고, 같은 방문의 다시 읽기는 표시를 두되 사라진 장만 뺀다")
  func marksLastOnlyForTheVisit() async throws {
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let first = await model.open()
    model.markForDeletionTapped()
    model.markForDeletionTapped()

    try await photoStore.delete(ids: ["s2"])
    model.libraryStoreChanged()
    await waitUntil { model.content.ids == ["s1", "s3"] }
    #expect(model.markedIDs == ["s1"])
    await cancelAndWait(first)

    let second = await model.open()
    #expect(model.markedIDs.isEmpty)
    #expect(model.keptCount == 0)

    await cancelAndWait(second)
  }

  @Test("처음 읽기에 실패하면 실패이고, 다시 시도하면 목록이 보이며, 실패가 아니면 무반응이다")
  func retryAfterFailure() async {
    let gates = CallGates(holding: [1])
    let photoStore = CleanupFixture.store(
      captureInboxErrors: [0: .failed],
      onCaptureInboxScreenshots: { await gates.pass($0) }
    )
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let appear = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    #expect(model.content == .loading)
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    await waitUntil { model.content.ids != nil }

    model.retryButtonTapped()
    await settle()
    #expect(photoStore.captureInboxCallCount == 2)

    await cancelAndWait(appear)
  }

  @Test("다시 읽기에 실패하면 지난 목록을 둔다")
  func reloadFailureKeepsList() async {
    let gates = CallGates(holding: [2])
    let photoStore = CleanupFixture.store(
      captureInboxErrors: [1: .failed],
      onCaptureInboxScreenshots: { await gates.pass($0) }
    )
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let appear = await model.open()

    model.libraryStoreChanged()
    await waitUntil { photoStore.captureInboxCallCount == 2 }
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.content.ids == ["s1", "s2", "s3"])

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 실패이고 삭제 버튼은 무반응이다")
  func missingStoreShowsFailed() async {
    let library = CleanupFixture.library()
    let model = CleanupFixture.inboxModel(library: library, photoStore: nil)

    await model.onAppear(visit: UUID())
    await model.deleteButtonTapped()
    await model.keepTapped()

    #expect(model.content == .failed)
    #expect(library.deletionRequests.isEmpty)
  }

  @Test("화면이 열려 있으면 저장소 변경과 날짜 변경에 다시 읽고, 닫혀 있으면 읽지 않는다")
  func signalsReloadOnlyWhileOpen() async {
    let clock = CleanupFixture.clock()
    let photoStore = CleanupFixture.store()
    let model = CleanupFixture.inboxModel(photoStore: photoStore, clock: clock)
    model.libraryStoreChanged()
    model.dayChanged()
    await settle()
    #expect(photoStore.captureInboxCallCount == 0)

    let appear = await model.open()
    model.libraryStoreChanged()
    await waitUntil { photoStore.captureInboxCallCount == 2 }
    clock.now = .seoul(2026, 10, 25, hour: 9)
    model.dayChanged()
    await waitUntil { photoStore.captureInboxCallCount == 3 }
    #expect(photoStore.captureInboxSinceArguments.last == .seoul(2026, 9, 26, hour: 0))

    await cancelAndWait(appear)
    model.libraryStoreChanged()
    model.dayChanged()
    await settle()
    #expect(photoStore.captureInboxCallCount == 3)
  }

  @Test("제한 접근이면 알리고, 사진 더 선택은 선택 화면을 띄운 뒤 접근 상태를 다시 읽는다")
  func limitedAccessAndPicker() async {
    let library = CleanupFixture.library(state: .limited)
    let model = CleanupFixture.inboxModel(library: library, photoStore: CleanupFixture.store())
    #expect(model.isLimited)

    library.sendIncrementalChange(accessState: .authorized)
    await model.selectMorePhotosTapped()

    #expect(library.limitedPickerPresentCount == 1)
    #expect(!model.isLimited)
  }

  @Test("저장소 변경 신호가 접근 상태를 다시 읽는다")
  func storeChangeRefreshesLimitedState() async {
    let library = CleanupFixture.library(state: .limited)
    let model = CleanupFixture.inboxModel(library: library, photoStore: CleanupFixture.store())
    let appear = await model.open()

    library.sendIncrementalChange(accessState: .authorized)
    model.libraryStoreChanged()
    await waitUntil { !model.isLimited }

    await cancelAndWait(appear)
  }
}
