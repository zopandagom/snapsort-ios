import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 정리 화면의 체크 원 끌어 선택: 방향·범위식·섹션과 묶음 넘기·남길 장·무시하는 입력·다른 선택 이벤트
/// (docs/ARCHITECTURE.md §4 정리 도우미 선택). 다시 읽기·삭제·방문과의 겹침은 `CleanupModelDragSelectionOverlapTests`.
/// 기본 데이터(`CleanupFixture`)의 화면 순서는 `expired`·`estimated`(만료됨) → `used`(사용함), 기본 선택은 `expired`·`used` 다.
/// 비슷한 사진 데이터(`CleanupModelSimilarPhotoTests`)는 그 뒤에 묶음 A(`a1`·`a2` 남김·`a3`)와 묶음 B(`b1`·`b2` 남김)가 이어진다.
@MainActor
struct CleanupModelDragSelectionTests {
  @Test("골라져 있지 않은 줄에서 끌면 시작 줄부터 고르고, 섹션을 넘어 지금 줄까지 고른다")
  func dragFromUnselectedSelectsRange() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()
    model.candidateToggled(id: "used")

    model.dragSelectionBegan(id: "estimated")
    #expect(model.isDragSelecting)
    #expect(model.selectedIDs == ["expired", "estimated"])
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    await cancelAndWait(appear)
  }

  @Test("골라져 있는 줄에서 끌면 시작 줄부터 풀고, 지금 줄까지 푼다")
  func dragFromSelectedDeselectsRange() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    model.dragSelectionBegan(id: "expired")
    #expect(model.selectedIDs == ["used"])
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs.isEmpty)

    await cancelAndWait(appear)
  }

  @Test("범위를 늘렸다 줄이면 범위 밖으로 돌아온 줄은 끌기 전 상태이고, 시작 줄 위로 가면 범위가 위로 바뀐다")
  func shrinkingRangeRestoresPreDragState() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()
    model.candidateToggled(id: "expired")
    model.candidateToggled(id: "used")

    model.dragSelectionBegan(id: "estimated")
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["estimated", "used"])
    model.dragSelectionMoved(to: "estimated")
    #expect(model.selectedIDs == ["estimated"])
    model.dragSelectionMoved(to: "expired")
    #expect(model.selectedIDs == ["expired", "estimated"])
    model.dragSelectionEnded()

    // 푸는 끌기에서 돌아온 줄은 골라진 채로 돌아간다.
    model.candidateToggled(id: "used")
    model.dragSelectionBegan(id: "expired")
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs.isEmpty)
    model.dragSelectionMoved(to: "expired")
    #expect(model.selectedIDs == ["estimated", "used"])

    await cancelAndWait(appear)
  }

  @Test("끌기는 기프티콘 섹션과 비슷한 사진 묶음을 넘어 화면 순서로 이어진다")
  func dragCrossesSimilarPhotoGroups() async {
    let model = CleanupModelSimilarPhotoTests.model(photoStore: CleanupModelSimilarPhotoTests.store())
    let appear = await model.open()
    #expect(model.selectedIDs == ["expired", "used", "a1", "a3", "b1"])

    model.dragSelectionBegan(id: "used")
    model.dragSelectionMoved(to: "b1")
    #expect(model.selectedIDs == ["expired"])

    await cancelAndWait(appear)
  }

  @Test("고르는 끌기는 지나는 남길 장을 끌기 전 상태로 두고, 시작 줄이 남길 장이면 그 장은 고른다")
  func selectingDragSkipsKeptPhotos() async {
    let model = CleanupModelSimilarPhotoTests.model(photoStore: CleanupModelSimilarPhotoTests.store())
    let appear = await model.open()
    model.sectionSelectionToggled(.similarPhotos)
    #expect(model.selectedIDs == ["expired", "used"])

    model.dragSelectionBegan(id: "a1")
    model.dragSelectionMoved(to: "b2")
    #expect(model.selectedIDs == ["expired", "used", "a1", "a3", "b1"])
    model.dragSelectionEnded()

    model.dragSelectionBegan(id: "a2")
    #expect(model.selectedIDs.contains("a2"))
    model.dragSelectionMoved(to: "b2")
    #expect(model.selectedIDs == ["expired", "used", "a1", "a2", "a3", "b1"])

    await cancelAndWait(appear)
  }

  @Test("푸는 끌기는 남길 장도 푼다")
  func deselectingDragClearsKeptPhotos() async {
    let model = CleanupModelSimilarPhotoTests.model(photoStore: CleanupModelSimilarPhotoTests.store())
    let appear = await model.open()
    model.candidateToggled(id: "a2")
    model.candidateToggled(id: "b2")

    model.dragSelectionBegan(id: "a1")
    model.dragSelectionMoved(to: "b2")
    #expect(model.selectedIDs == ["expired", "used"])

    await cancelAndWait(appear)
  }

  @Test("목록에 없는 식별자, 불러오기 전, 끌기 없이 온 이동과 끝은 무시한다")
  func unknownIDsAreIgnored() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    model.dragSelectionBegan(id: "expired")
    #expect(!model.isDragSelecting)

    let appear = await model.open()
    model.dragSelectionMoved(to: "estimated")
    model.dragSelectionEnded()
    #expect(model.selectedIDs == ["expired", "used"])

    model.dragSelectionBegan(id: "today")
    #expect(!model.isDragSelecting)
    model.dragSelectionMoved(to: "estimated")
    #expect(model.selectedIDs == ["expired", "used"])

    model.dragSelectionBegan(id: "estimated")
    model.dragSelectionMoved(to: "missing")
    #expect(model.isDragSelecting)
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    await cancelAndWait(appear)
  }

  @Test("끌기 중 다른 선택 이벤트가 오면 끌기를 지금 선택으로 끝내고 그 이벤트를 처리하며, 무시되는 이벤트는 끌기를 둔다")
  func otherSelectionEventEndsDrag() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    model.dragSelectionBegan(id: "estimated")
    model.candidateToggled(id: "missing")
    model.sectionSelectionToggled(.similarPhotos)
    #expect(model.isDragSelecting)
    model.candidateToggled(id: "expired")
    #expect(!model.isDragSelecting)
    #expect(model.selectedIDs == ["estimated", "used"])
    model.dragSelectionMoved(to: "expired")
    #expect(model.selectedIDs == ["estimated", "used"])

    model.dragSelectionBegan(id: "estimated")
    #expect(model.selectedIDs == ["used"])
    model.sectionSelectionToggled(.expiredGifticons)
    #expect(!model.isDragSelecting)
    #expect(model.selectedIDs == ["expired", "estimated", "used"])

    await cancelAndWait(appear)
  }

  @Test("끌기 중 다른 줄에서 다시 시작하면 지난 끌기의 결과를 끌기 전 상태로 새로 시작한다")
  func beganDuringDragRestartsFromCurrentSelection() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    model.dragSelectionBegan(id: "estimated")
    #expect(model.selectedIDs == ["expired", "estimated", "used"])
    model.dragSelectionBegan(id: "used")
    #expect(model.selectedIDs == ["expired", "estimated"])
    model.dragSelectionMoved(to: "estimated")
    #expect(model.selectedIDs == ["expired"])
    model.dragSelectionMoved(to: "used")
    #expect(model.selectedIDs == ["expired", "estimated"])

    await cancelAndWait(appear)
  }

  @Test("끌기를 끝내면 선택을 그대로 두고 그 뒤 이동은 무시한다")
  func endedKeepsSelection() async {
    let model = CleanupFixture.model(photoStore: CleanupFixture.store())
    let appear = await model.open()

    model.dragSelectionBegan(id: "expired")
    model.dragSelectionMoved(to: "used")
    model.dragSelectionEnded()
    #expect(!model.isDragSelecting)
    #expect(model.selectedIDs.isEmpty)
    model.dragSelectionMoved(to: "expired")
    model.dragSelectionEnded()
    #expect(model.selectedIDs.isEmpty)

    await cancelAndWait(appear)
  }
}
