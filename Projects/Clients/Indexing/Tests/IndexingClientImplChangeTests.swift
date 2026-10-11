import Core
import Foundation
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import Testing
@testable import IndexingImpl

/// 처음 비교 뒤의 보관함 변경(증분·전체 다시 조회) 반영.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplChangeTests {
  @Test("미룬 이미지는 전체 다시 조회 때 다시 분석한다")
  func retriesSkippedImagesOnReloadAll() async {
    let library: [ImageAsset] = [.stub(id: "broken"), .stub(id: "ok")]
    let fixture = Fixture(library: library, classifyFailures: ["broken"])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.classifyFailures.removeAll()
    fixture.photoLibrary.sendReloadAll(imageAssets: library)
    let finished = await progress.next { $0.indexedCount == 2 }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
  }

  @Test("보관함 변경으로 추가된 이미지를 분석하고 삭제된 이미지의 결과를 지운다")
  func appliesIncrementalChanges() async {
    let added = ImageAsset.stub(id: "added")
    let fixture = Fixture(library: [.stub(id: "a"), .stub(id: "b")], loadable: [added])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendIncrementalChange(inserted: [added], removed: ["a"])
    let finished = await progress.next { $0.isFinished && fixture.store.images.map(\.id) == ["added", "b"] }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
    #expect(fixture.store.deletedBatches == [["a"]])
  }

  @Test("같은 변경이 다시 와도 이미 분석한 이미지는 다시 분석하지 않는다")
  func ignoresRepeatedChanges() async {
    let added = ImageAsset.stub(id: "added")
    let later = ImageAsset.stub(id: "later")
    let fixture = Fixture(library: [.stub(id: "a")], loadable: [added, later])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendIncrementalChange(inserted: [added])
    fixture.photoLibrary.sendIncrementalChange(inserted: [added, added])
    // 변경은 순서대로 반영되므로, 마지막 변경까지 반영되면 앞의 두 변경도 끝났다.
    fixture.photoLibrary.sendIncrementalChange(inserted: [later])
    _ = await progress.next { $0.totalCount == 3 && $0.isFinished }

    let addedRequests = fixture.photoLibrary.loadImageRequests.filter { $0.id == "added" && $0.size == .thumbnail }
    #expect(addedRequests.count == 1)
  }

  @Test("전체 다시 조회 알림이면 보관함 전체를 저장소와 다시 비교한다")
  func reloadsAllOnReloadAllChange() async {
    let added = ImageAsset.stub(id: "c")
    let fixture = Fixture(library: [.stub(id: "a"), .stub(id: "b")], loadable: [added])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendReloadAll(imageAssets: [.stub(id: "b"), added])
    let finished = await progress.next { $0.isFinished && fixture.store.images.map(\.id) == ["b", "c"] }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
  }

  @Test("실행 중에 읽기 권한을 잃으면 저장 결과를 지우지 않고 끝낸다")
  func keepsStoreWhenAccessDeniedDuringRun() async {
    let fixture = Fixture(library: [.stub(id: "a")])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendReloadAll(imageAssets: [], accessState: .denied)
    // 권한이 없으면 비교하지 않고 끝나므로 스트림이 끝날 때까지 읽는다.
    while await progress.next() != nil {}

    #expect(fixture.store.deletedBatches.isEmpty)
    #expect(fixture.store.images.map(\.id) == ["a"])
  }

  @Test("제한 접근으로 바뀌면 고르지 않은 사진의 결과를 지운다")
  func deletesUnselectedImagesWhenLimited() async {
    let fixture = Fixture(library: [.stub(id: "selected"), .stub(id: "unselected")])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendReloadAll(imageAssets: [.stub(id: "selected")], accessState: .limited)
    let finished = await progress.next { $0.totalCount == 1 && $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    #expect(fixture.store.images.map(\.id) == ["selected"])
  }

  @Test("보관함이 그대로인 변경이 다시 오면 여행을 다시 판정·저장하지 않는다")
  func skipsTripsWhenLibraryUnchanged() async {
    let added = ImageAsset.stub(id: "added")
    let fixture = Fixture(library: [.stub(id: "a")], loadable: [added])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendIncrementalChange(inserted: [added])
    _ = await progress.next { $0.totalCount == 2 && $0.isFinished }
    let countAfterChange = fixture.store.replaceTripsCount
    // 같은 변경 두 번 뒤에 보관함을 바꾸는 변경을 보내, 앞의 두 변경이 반영된 뒤에 확인한다.
    fixture.photoLibrary.sendIncrementalChange(inserted: [added])
    fixture.photoLibrary.sendIncrementalChange(inserted: [added])
    fixture.photoLibrary.sendIncrementalChange(removed: ["a"])
    _ = await progress.next { $0.totalCount == 1 && $0.isFinished }

    #expect(countAfterChange == 2)
    #expect(fixture.store.replaceTripsCount == 3)
  }

  @Test("미룬 이미지가 변경으로 다시 와도 다시 분석하지 않는다")
  func ignoresSkippedImagesInChanges() async {
    let later = ImageAsset.stub(id: "later")
    let icloud = ImageAsset.stub(id: "icloud")
    let fixture = Fixture(library: [icloud], loadable: [later], loadErrors: ["icloud": .notAvailableLocally])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }
    fixture.photoLibrary.sendIncrementalChange(inserted: [icloud, later])
    let finished = await progress.next { $0.totalCount == 2 && $0.indexedCount == 1 }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 1))
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.id == "icloud" } == 1)
  }
}
