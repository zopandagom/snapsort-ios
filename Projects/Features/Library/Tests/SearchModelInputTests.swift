import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 검색 Model 의 입력 처리. 대기(debounce)·늦은 결과 버리기·빈 검색어를 다룬다.
@MainActor
struct SearchModelInputTests {
  @Test("입력은 0.25초 대기 뒤에 거른다")
  func queryWaitsForDebounceInterval() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("스타")
    await waitUntil { model.results != nil }
    #expect(probe.waits == [.milliseconds(250)])
    #expect(SearchModel.debounceInterval == .milliseconds(250))

    await cancelAndWait(appear)
  }

  @Test("대조가 끝나기 전에 다음 검색어가 오면 앞 검색어의 늦은 결과를 버린다")
  func lateMatchResultIsDropped() async {
    let matchGates = CallGates(holding: [0], ignoresCancellation: true)
    defer { matchGates.open(0) }
    let photoStore = PhotoStoreClientFake(images: [
      .searchable(id: "abc", ["abc"], at: .seoul(2026, 10, 2, hour: 9)),
      .searchable(id: "a", ["a"], at: .seoul(2026, 10, 1, hour: 9)),
    ])
    let (model, _) = SearchFixture.model(photoStore: photoStore, matchGates: matchGates)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("a")
    await waitUntil { matchGates.hasEntered(0) }
    model.queryChanged("ab")
    await waitUntil { model.results?.query == "ab" }
    matchGates.open(0)
    await settle()
    #expect(model.results?.query == "ab")
    #expect(model.resultImageIDs == ["abc"])

    await cancelAndWait(appear)
  }

  @Test("대기 중에 다음 입력이 오면 앞 대기는 취소되어 대조는 한 번만 한다")
  func debounceCancelsPreviousWait() async {
    let waitGates = CallGates(holding: [0])
    defer { waitGates.open(0) }
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore, waitGates: waitGates)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("스")
    await waitUntil { waitGates.hasEntered(0) }
    model.queryChanged("스타")
    await waitUntil { model.results?.query == "스타" }
    waitGates.open(0)
    await settle()
    #expect(probe.matches == ["스타"])
    #expect(model.results?.query == "스타")

    await cancelAndWait(appear)
  }

  @Test("빈 검색어와 공백만 있는 검색어는 결과를 바로 비우고 대조하지 않는다")
  func emptyQueryClearsWithoutMatching() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    model.queryChanged("스타벅스")
    await waitUntil { model.results != nil }
    let matchCount = probe.matches.count

    model.queryChanged("")
    #expect(model.results == nil)
    #expect(!model.hasQuery)
    model.queryChanged("스타벅스")
    await waitUntil { model.results != nil }
    model.queryChanged("  \u{3000} ")
    #expect(model.results == nil)
    #expect(!model.hasQuery)
    await settle()
    #expect(probe.matches.count == matchCount + 1)

    await cancelAndWait(appear)
  }

  @Test("검색어를 지운 뒤 늦게 끝난 대조 결과는 버린다")
  func lateMatchAfterClearIsDropped() async {
    let matchGates = CallGates(holding: [0], ignoresCancellation: true)
    defer { matchGates.open(0) }
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, _) = SearchFixture.model(photoStore: photoStore, matchGates: matchGates)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("스타벅스")
    await waitUntil { matchGates.hasEntered(0) }
    model.queryChanged("")
    matchGates.open(0)
    await settle()
    #expect(model.results == nil)

    await cancelAndWait(appear)
  }

  @Test("같은 글자가 다시 오면 무시한다")
  func sameTextIsIgnored() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("스타")
    model.queryChanged("스타")
    await waitUntil { model.results != nil }
    await settle()
    #expect(probe.waits.count == 1)
    #expect(probe.matches == ["스타"])

    await cancelAndWait(appear)
  }

  @Test("검색어는 고치지 않고 담는다")
  func queryIsKeptAsTyped() {
    let (model, _) = SearchFixture.model(photoStore: PhotoStoreClientFake())
    model.queryChanged("  Coupang  ")
    #expect(model.query == "  Coupang  ")
  }

  @Test("색인을 만들기 전에 넣은 검색어는 색인이 만들어지면 바로 거른다")
  func queryBeforeIndexIsMatchedWhenReady() async {
    let buildGates = CallGates(holding: [0], ignoresCancellation: true)
    defer { buildGates.open(0) }
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks])
    let (model, probe) = SearchFixture.model(photoStore: photoStore, buildGates: buildGates)
    let appear = Task { await model.onAppear() }
    await waitUntil { buildGates.hasEntered(0) }

    model.queryChanged("스타벅스")
    await settle()
    #expect(model.results == nil)
    #expect(probe.matches.isEmpty)

    buildGates.open(0)
    await waitUntil { model.resultImageIDs == ["starbucks"] }
    // 색인 뒤의 대조는 대기 없이 바로 한다.
    #expect(probe.waits.count == 1)

    await cancelAndWait(appear)
  }
}
