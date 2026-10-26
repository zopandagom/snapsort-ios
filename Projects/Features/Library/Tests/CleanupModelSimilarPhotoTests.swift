import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 정리 화면의 비슷한 사진 섹션: 읽기·묶기·기본 선택·섹션 선택·삭제·실패·재진입 (docs/ARCHITECTURE.md §4 정리 도우미).
/// 기본 데이터(`CleanupFixture`)에 더해 묶음 A(어제 12시, 2초 간격 3장, 가운데가 가장 커서 남김)와 묶음 B(그제 12시, 3초 간격 2장,
/// 크기가 같아 최신이 남김), 묶음 A 바로 뒤에 저장한 글자 없는 기프티콘(벡터가 가까워도 빠진다)을 둔다.
/// 기본 데이터의 "photo" 는 벡터가 없는 대상이라 아직 비교하지 않은 1장이다.
@MainActor
struct CleanupModelSimilarPhotoTests {
  static let groupA = ["a1", "a2", "a3"]
  static let groupB = ["b1", "b2"]
  static let similarIDs = Self.groupA + Self.groupB + ["g1"]

  static func similar(
    id: String,
    _ creationDate: Date,
    value: Float?,
    pixelWidth: Int = 4032,
    categories: Set<ImageCategory> = [.people]
  ) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: creationDate, pixelWidth: pixelWidth),
      labels: [],
      textRecognition: .notNeeded,
      categories: categories,
      featurePrint: value.flatMap(self.featurePrint)
    )
  }

  /// 첫 원소만 `value` 인 벡터. 두 벡터의 거리는 첫 원소 차이다.
  static func featurePrint(_ value: Float) -> ImageFeaturePrint? {
    var values = [Float](repeating: 0, count: ImageFeaturePrint.elementCount)
    values[0] = value
    return ImageFeaturePrint(values: values)
  }

  static func photos() -> [IndexedImage] {
    let dayA = Date.seoul(2026, 10, 23, hour: 12)
    let dayB = Date.seoul(2026, 10, 22, hour: 12)
    return [
      Self.similar(id: "a1", dayA, value: 0),
      Self.similar(id: "a2", dayA.addingTimeInterval(2), value: 0.1, pixelWidth: 5712),
      Self.similar(id: "a3", dayA.addingTimeInterval(4), value: 0.2),
      Self.similar(id: "g1", dayA.addingTimeInterval(6), value: 0.25, categories: [.gifticon]),
      Self.similar(id: "b1", dayB, value: 3),
      Self.similar(id: "b2", dayB.addingTimeInterval(3), value: 3.05),
    ]
  }

  static func store(
    similarPhotoEntriesErrors: [Int: PhotoStoreError] = [:],
    onSimilarPhotoEntries: @escaping @Sendable (Int) async -> Void = { _ in }
  ) -> PhotoStoreClientFake {
    CleanupFixture.store(
      extra: self.photos(),
      similarPhotoEntriesErrors: similarPhotoEntriesErrors,
      onSimilarPhotoEntries: onSimilarPhotoEntries
    )
  }

  static func model(
    library: PhotoLibraryClientFake = CleanupFixture.library(containing: CleanupFixture.allIDs + Self.similarIDs),
    photoStore: PhotoStoreClientFake,
    findsSimilarPhotos: Bool = true,
    clock: TestClock = CleanupFixture.clock()
  ) -> CleanupModel {
    CleanupFixture.model(library: library, photoStore: photoStore, findsSimilarPhotos: findsSimilarPhotos, clock: clock)
  }

  @Test("벡터를 만들 수 없는 기기면 비슷한 사진을 조회하지 않아 섹션도 미비교 안내도 없다")
  func unavailableSkipsSimilarPhotos() async {
    let photoStore = Self.store()
    let model = Self.model(photoStore: photoStore, findsSimilarPhotos: false)
    let appear = await model.open()

    #expect(photoStore.similarPhotoEntriesCallCount == 0)
    #expect(model.content.sections?.sections.map(\.kind) == [.expiredGifticons, .usedGifticons])
    #expect(model.content.sections?.uncomparedPhotoCount == 0)

    await cancelAndWait(appear)
  }

  @Test("묶음을 최근 묶음부터 기프티콘 섹션 뒤에 보이고, 기프티콘 카테고리 사진은 묶지 않으며, 미비교 수를 담는다")
  func groupsSimilarPhotos() async throws {
    let model = Self.model(photoStore: Self.store())
    let appear = await model.open()

    let sections = try #require(model.content.sections)
    #expect(sections.sections.map(\.kind) == [.expiredGifticons, .usedGifticons, .similarPhotos])
    let similar = try #require(sections.sections.last)
    #expect(similar.groups.map { $0.candidates.map(\.id) } == [Self.groupA, Self.groupB])
    #expect(similar.candidates.filter(\.isKept).map(\.id) == ["a2", "b2"])
    #expect(similar.candidates.allSatisfy { $0.gifticon == nil })
    #expect(sections.uncomparedPhotoCount == 1)

    await cancelAndWait(appear)
  }

  @Test("첫 읽기에서 남길 장은 해제, 나머지는 선택이고 확보 용량에 든다")
  func selectsAllButKept() async {
    let model = Self.model(photoStore: Self.store())
    let appear = await model.open()

    #expect(model.selectedIDs == ["expired", "used", "a1", "a3", "b1"])
    let assets = Self.photos().map(\.asset).filter { ["a1", "a3", "b1"].contains($0.id) }
    let gifticons: [ImageAsset] = [.stub(id: "expired"), .stub(id: "used")]
    #expect(model.selectionBytes == CleanupSizeEstimate.bytes(of: gifticons + assets))

    await cancelAndWait(appear)
  }

  @Test("나중에 나타난 묶음은 선택하지 않는다")
  func laterGroupIsUnselected() async throws {
    let photoStore = Self.store()
    let model = Self.model(photoStore: photoStore)
    let appear = await model.open()
    let day = Date.seoul(2026, 10, 24, hour: 8)

    try await photoStore.save([
      Self.similar(id: "c1", day, value: 5),
      Self.similar(id: "c2", day.addingTimeInterval(1), value: 5.1),
    ])
    model.libraryStoreChanged()
    await waitUntil { model.content.candidateIDs?.contains("c1") == true }

    #expect(model.content.sections?.sections.last?.groups.first?.candidates.map(\.id) == ["c1", "c2"])
    #expect(model.selectedIDs == ["expired", "used", "a1", "a3", "b1"])

    await cancelAndWait(appear)
  }

  @Test("섹션 선택은 남길 장을 빼고 고르고, 그만큼 골라져 있으면 남길 장까지 모두 푼다")
  func sectionToggleSkipsKept() async {
    let model = Self.model(photoStore: Self.store())
    let appear = await model.open()

    model.sectionSelectionToggled(.similarPhotos)
    #expect(model.selectedIDs == ["expired", "used"])
    model.sectionSelectionToggled(.similarPhotos)
    #expect(model.selectedIDs == ["expired", "used", "a1", "a3", "b1"])

    model.candidateToggled(id: "a2")
    #expect(model.selectedIDs.contains("a2"))
    model.sectionSelectionToggled(.similarPhotos)
    #expect(model.selectedIDs == ["expired", "used"])

    await cancelAndWait(appear)
  }

  @Test("비슷한 사진을 지우면 남은 장이 하나인 묶음은 사라지고, 새 방문에서는 저장소가 돌려줘도 해제로 보인다")
  func deletingDissolvesGroups() async {
    let library = CleanupFixture.library(containing: CleanupFixture.allIDs + Self.similarIDs)
    let model = Self.model(library: library, photoStore: Self.store())
    let appear = await model.open()
    model.sectionSelectionToggled(.expiredGifticons)
    model.sectionSelectionToggled(.expiredGifticons)
    model.sectionSelectionToggled(.usedGifticons)
    model.candidateToggled(id: "a3")
    #expect(model.selectedIDs == ["a1", "b1"])

    await model.deleteButtonTapped()

    #expect(library.deletionRequests == [["a1", "b1"]])
    #expect(model.content.sections?.sections.last?.groups.map { $0.candidates.map(\.id) } == [["a2", "a3"]])
    #expect(model.notice == CleanupNotice(deletedCount: 2, skippedCount: 0))
    await cancelAndWait(appear)

    // Fake 보관함은 저장소 행을 지우지 않으므로 저장소는 지운 사진을 계속 돌려준다.
    let next = await model.open()
    #expect(model.content.sections?.sections.last?.groups.map { $0.candidates.map(\.id) } == [Self.groupA, Self.groupB])
    #expect(model.selectedIDs == ["expired", "used", "a3"])

    await cancelAndWait(next)
  }

  @Test("남길 장을 지운 뒤 새 방문에서 저장소가 아직 돌려줘도 그 장은 남길 장이 아니라 해제로 보이고, 남은 장에서 남길 장을 고른다")
  func deletedKeptPhotoIsNotKeptAgain() async {
    let library = CleanupFixture.library(containing: CleanupFixture.allIDs + Self.similarIDs)
    let model = Self.model(library: library, photoStore: Self.store())
    let appear = await model.open()
    for id in model.selectedIDs {
      model.candidateToggled(id: id)
    }
    model.candidateToggled(id: "a2")
    #expect(model.selectedIDs == ["a2"])

    await model.deleteButtonTapped()

    #expect(library.deletionRequests == [["a2"]])
    await cancelAndWait(appear)

    // Fake 보관함은 저장소 행을 지우지 않으므로 저장소는 지운 a2 를 계속 돌려준다.
    // a2 는 남길 장이 아니고(해제), 남은 a1·a3 중 크기가 같아 최신인 a3 이 남긴다. a1 만 기본 선택이다.
    let next = await model.open()
    let groupA = model.content.sections?.sections.last?.groups.first
    #expect(groupA?.candidates.map(\.id) == Self.groupA)
    #expect(groupA?.candidates.filter { !$0.isSelectedByDefault }.map(\.id) == ["a3"])
    #expect(model.selectedIDs == ["expired", "used", "a1", "b1"])

    await cancelAndWait(next)
  }

  @Test("비슷한 사진 처음 읽기에 실패하면 실패이고, 다시 읽기에 실패하면 지난 목록을 둔다")
  func similarPhotoFailures() async {
    let photoStore = Self.store(similarPhotoEntriesErrors: [0: .failed, 2: .failed])
    let model = Self.model(photoStore: photoStore)
    let appear = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    await waitUntil { model.content.candidateIDs != nil }
    let content = model.content
    #expect(content.sections?.sections.last?.kind == .similarPhotos)

    model.libraryStoreChanged()
    await waitUntil { photoStore.similarPhotoEntriesCallCount == 3 }
    await settle()
    #expect(model.content == content)

    await cancelAndWait(appear)
  }

  @Test("비슷한 사진을 읽는 동안 화면을 닫으면 기프티콘도 반영하지 않는다")
  func closingDuringSimilarPhotoReadDropsResult() async {
    let gates = CallGates(holding: [0])
    let photoStore = Self.store(onSimilarPhotoEntries: { await gates.pass($0) })
    let model = Self.model(photoStore: photoStore)

    let appear = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { gates.hasEntered(0) }
    #expect(photoStore.gifticonsCallCount == 1)
    await cancelAndWait(appear)
    gates.open(0)
    await settle()

    #expect(model.content == .loading)
    #expect(model.selectedIDs.isEmpty)
  }

  @Test("비슷한 사진을 읽는 동안 새 방문이 시작되면 늦게 끝난 지난 결과를 버린다")
  func reentryDropsStaleSimilarPhotoRead() async throws {
    let gates = CallGates(holding: [0])
    let photoStore = Self.store(onSimilarPhotoEntries: { await gates.pass($0) })
    let model = Self.model(photoStore: photoStore)
    let first = Task { await model.onAppear(visit: UUID()) }
    await waitUntil { gates.hasEntered(0) }

    try await photoStore.delete(ids: ["b2"])
    let second = await model.open()
    #expect(model.content.sections?.sections.last?.groups.map { $0.candidates.map(\.id) } == [Self.groupA])
    gates.open(0)
    await settle()

    #expect(model.content.sections?.sections.last?.groups.map { $0.candidates.map(\.id) } == [Self.groupA])

    first.cancel()
    await cancelAndWait(second)
  }

  @Test("날짜가 바뀌어도 비슷한 사진을 다시 읽지 않는다")
  func dayChangedDoesNotReadSimilarPhotos() async {
    let clock = CleanupFixture.clock()
    let photoStore = Self.store()
    let model = Self.model(photoStore: photoStore, clock: clock)
    let appear = await model.open()

    clock.now = .seoul(2026, 10, 25, hour: 9)
    model.dayChanged()

    #expect(photoStore.similarPhotoEntriesCallCount == 1)
    #expect(model.content.sections?.sections.last?.groups.count == 2)

    await cancelAndWait(appear)
  }

  @Test("묶음이 없어도 미비교 사진이 있으면 그 수를 담고, 후보가 없으면 빈 목록이다")
  func uncomparedWithoutGroups() async {
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "photo", .seoul(2026, 10, 22, hour: 12))])
    let model = Self.model(photoStore: photoStore)
    let appear = await model.open()

    #expect(model.content.sections?.isEmpty == true)
    #expect(model.content.sections?.uncomparedPhotoCount == 1)

    await cancelAndWait(appear)
  }
}
