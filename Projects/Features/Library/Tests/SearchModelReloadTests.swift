import Core
import Foundation
import Observation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 검색 Model 의 실패·다시 읽기. 읽기를 붙잡을 때는 `onSearchEntries` 에 `CallGates` 를,
/// 실패는 `searchEntriesErrors` 를 쓴다.
@MainActor
struct SearchModelReloadTests {
  // MARK: - 실패와 다시 시도

  @Test("처음 읽지 못하면 검색어와 관계없이 실패이고, 다시 시도하면 불러오는 중을 거쳐 결과가 보인다")
  func retryAfterFailure() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [SearchFixture.starbucks],
      searchEntriesErrors: [0: .failed],
      onSearchEntries: { await gates.pass($0) }
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .failed }

    // 실패한 채 입력해도 실패 화면이 남는다.
    model.queryChanged("스타벅스")
    await settle()
    #expect(model.loadState == .failed)
    #expect(model.results == nil)

    model.retryButtonTapped()
    #expect(model.loadState == .loading)
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    await waitUntil { model.resultImageIDs == ["starbucks"] }
    #expect(model.loadState == .loaded)

    await cancelAndWait(appear)
  }

  @Test("실패가 아닐 때와 닫혀 있을 때는 다시 시도에 반응하지 않는다")
  func retryIgnoredUnlessFailedAndOpen() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks], searchEntriesErrors: [0: .failed])
    let (model, _) = SearchFixture.model(photoStore: photoStore)

    // 닫혀 있다.
    model.retryButtonTapped()
    #expect(photoStore.searchEntriesCallCount == 0)

    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .failed }
    await cancelAndWait(appear)
    model.retryButtonTapped()
    #expect(model.loadState == .failed)

    let second = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    // 실패가 아니다. 처음 읽기(실패)와 두 번째 읽기, 모두 둘이다.
    model.retryButtonTapped()
    await settle()
    #expect(photoStore.searchEntriesCallCount == 2)

    await cancelAndWait(second)
  }

  @Test("장소 캐시 읽기에 실패해도 처음 읽기는 실패다")
  func placesFailureFailsFirstRead() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      placeError: .failed
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .failed }
    await cancelAndWait(appear)
  }

  // MARK: - 저장소 변경 신호

  @Test("저장소 변경 신호로 다시 읽어 새 사진이 결과에 들고, 대기 없이 바로 다시 거른다")
  func storeChangeReloadsWithoutWaiting() async throws {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs == ["starbucks"] }
    let waitCount = probe.waits.count

    try await photoStore.save([.searchable(id: "new", ["새 영수증 스타벅스"], at: .seoul(2026, 10, 20, hour: 9))])
    model.libraryStoreChanged()
    await waitUntil { model.resultImageIDs == ["new", "starbucks"] }
    #expect(probe.waits.count == waitCount)
    #expect(model.results?.query == "스타벅스")

    await cancelAndWait(appear)
  }

  @Test("읽는 도중 신호 여러 개는 한 번으로 합친다")
  func storeChangesCoalesce() async {
    let gates = CallGates(holding: [1, 2])
    let photoStore = PhotoStoreClientFake(
      images: [SearchFixture.starbucks],
      onSearchEntries: { await gates.pass($0) }
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    gates.open(1)
    await waitUntil { gates.hasEntered(2) }
    gates.open(2)
    await settle()
    #expect(photoStore.searchEntriesCallCount == 3)

    await cancelAndWait(appear)
  }

  @Test("닫혀 있는 동안 신호는 버린다")
  func storeChangeWhileClosedIsDropped() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    model.libraryStoreChanged()
    model.dayChanged()
    await settle()
    #expect(photoStore.searchEntriesCallCount == 0)

    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    await cancelAndWait(appear)
    model.libraryStoreChanged()
    await settle()
    #expect(photoStore.searchEntriesCallCount == 1)
  }

  @Test("다시 읽기에 실패하면 지난 색인과 결과를 둔다")
  func reloadFailureKeepsResults() async {
    // 실패한 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째를 붙잡아 실패 처리 뒤의 상태를 본다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(
      images: [SearchFixture.starbucks],
      searchEntriesErrors: [1: .failed],
      onSearchEntries: { await gates.pass($0) }
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs == ["starbucks"] }

    model.libraryStoreChanged()
    await settle()
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.loadState == .loaded)
    #expect(model.resultImageIDs == ["starbucks"])

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("다시 읽어도 결과가 같으면 결과를 대입하지 않아 다시 그리지 않는다")
  func unchangedResultsAreNotReassigned() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [SearchFixture.starbucks],
      onSearchEntries: { await gates.pass($0) }
    )
    let (model, probe) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs == ["starbucks"] }
    let changes = CallCounter()
    withObservationTracking {
      _ = model.results
    } onChange: {
      _ = changes.next()
    }

    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    gates.open(1)
    // 읽은 뒤 바로 다시 거른 대조까지 끝나기를 기다린다.
    await waitUntil { probe.matches.count == 2 }
    await settle()
    #expect(changes.next() == 0)

    await cancelAndWait(appear)
  }

  @Test("읽는 도중 입력은 지난 색인으로 거르고, 색인이 만들어지면 새 색인으로 대기 없이 다시 거른다")
  func queryDuringReloadUsesOldIndexThenNew() async throws {
    let buildGates = CallGates(holding: [1], ignoresCancellation: true)
    defer { buildGates.open(1) }
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore, buildGates: buildGates)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    try await photoStore.save([.searchable(id: "new", ["새 영수증 스타벅스"], at: .seoul(2026, 10, 20, hour: 9))])
    model.libraryStoreChanged()
    await waitUntil { buildGates.hasEntered(1) }
    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs == ["starbucks"] }
    let waitCount = probe.waits.count

    buildGates.open(1)
    await waitUntil { model.resultImageIDs == ["new", "starbucks"] }
    #expect(probe.waits.count == waitCount)

    await cancelAndWait(appear)
  }
}
