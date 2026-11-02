import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 넘겨 보는 사진 상세의 큰 이미지 창(지금 장 ± 1). 상세 수명은 닫힐 때까지(Task 가 취소될 때까지) 돌아오지 않으므로,
/// Task 로 부르고 상태를 확인한 뒤 취소하고 끝나기를 기다린다.
@MainActor
struct CategoryModelDetailPagerTests {
  static let ids = (0 ..< 5).map { "p\($0)" }

  @Test("상세를 열면 지금 장을 가장 큰 버전으로 먼저 읽고, 끝난 뒤에야 앞뒤 장을 읽는다")
  func readsCurrentPageFirst() async {
    let gates = CallGates(holding: [0])
    let photoLibrary = Self.library(loadGate: { id in
      if id == "p2" {
        await gates.pass(0)
      }
    })
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)

    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 2, origin: nil) }
    await waitUntil { gates.hasEntered(0) }
    await settle()
    #expect(photoLibrary.loadImageRequests == [LoadImageRequest(id: "p2", size: .largestAvailable)])
    #expect(model.detailImages.isEmpty)

    gates.open(0)
    await waitUntil { Self.loadedIDs(model) == ["p1", "p2", "p3"] }
    #expect(photoLibrary.loadImageRequests.count == 3)
    #expect(photoLibrary.loadImageRequests.allSatisfy { $0.size == .largestAvailable })

    await cancelAndWait(detail)
  }

  @Test("지금 장을 볼 수 없어도(iCloud 에만 있음) 앞뒤 장을 읽는다")
  func readsNeighborsAfterUnavailableCurrentPage() async {
    var results = Self.results
    results["p2"] = .failure(.notAvailableLocally)
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: results)
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)

    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 2, origin: nil) }
    await waitUntil { model.detailImages["p1"]?.image != nil && model.detailImages["p3"]?.image != nil }
    #expect(model.detailImages["p2"]?.unavailableReason == .inCloudOnly)

    await cancelAndWait(detail)
  }

  @Test("취소하지 않았는데 읽기가 취소로 끝나면(사진 보관함이 스스로 취소) 그 장은 실패로 두고 다시 읽지 않으며 앞뒤 장을 읽는다")
  func treatsUnrequestedCancellationAsFailure() async {
    var results = Self.results
    results["p2"] = .failure(.cancelled)
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: results)
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)

    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 2, origin: nil) }
    await waitUntil { model.detailImages["p1"]?.image != nil && model.detailImages["p3"]?.image != nil }
    await settle()
    #expect(model.detailImages["p2"]?.unavailableReason == .failed)
    #expect(photoLibrary.loadImageRequests.count { $0.id == "p2" } == 1)

    await cancelAndWait(detail)
  }

  @Test("넘기면 창 밖 이미지를 놓고 새 이웃을 읽으며, 창 안에 이미 읽은 장은 다시 읽지 않는다")
  func pageChangeMovesWindow() async {
    let photoLibrary = Self.library()
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 1, origin: nil) }
    await waitUntil { Self.loadedIDs(model) == ["p0", "p1", "p2"] }

    model.detailPageChanged(index: 2, id: "p2")
    #expect(model.detailImages["p0"] == nil)
    await waitUntil { Self.loadedIDs(model) == ["p1", "p2", "p3"] }
    #expect(photoLibrary.loadImageRequests.map(\.id) == ["p1", "p0", "p2", "p3"])

    await cancelAndWait(detail)
  }

  @Test("창 밖으로 나간 읽는 중 요청은 취소되고 늦은 결과가 남지 않는다")
  func leavingWindowCancelsLoad() async {
    // 취소돼도 열 때까지 기다리다 늦게 끝난다.
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoLibrary = Self.library(loadGate: { id in
      if id == "p3" {
        await gates.pass(0)
      }
    })
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 2, origin: nil) }
    await waitUntil { gates.hasEntered(0) && model.detailImages["p1"]?.image != nil }

    model.detailPageChanged(index: 1, id: "p1")
    model.detailPageChanged(index: 0, id: "p0")
    await waitUntil { Self.loadedIDs(model) == ["p0", "p1"] }
    gates.open(0)
    await settle()
    #expect(Self.loadedIDs(model) == ["p0", "p1"])

    await cancelAndWait(detail)
  }

  @Test("빠르게 여러 장 넘기면 마지막 창의 장만 남는다")
  func fastPagingKeepsOnlyLastWindow() async {
    let ids = (0 ..< 10).map { "p\($0)" }
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { ($0, .success(.stub())) })
    )
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: ids, index: 0, origin: nil) }

    for index in 1 ... 6 {
      model.detailPageChanged(index: index, id: ids[index])
      await Task.yield()
    }
    await waitUntil { Self.loadedIDs(model) == ["p5", "p6", "p7"] }
    await settle()
    #expect(Self.loadedIDs(model) == ["p5", "p6", "p7"])

    await cancelAndWait(detail)
  }

  @Test("처음·마지막 장과 한 장짜리 섹션에서 창이 범위를 넘지 않는다")
  func windowStaysInBounds() async {
    let photoLibrary = Self.library()
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 0, origin: nil) }
    await waitUntil { Self.loadedIDs(model) == ["p0", "p1"] }

    model.detailPageChanged(index: 4, id: "p4")
    await waitUntil { Self.loadedIDs(model) == ["p3", "p4"] }
    await settle()
    #expect(photoLibrary.loadImageRequests.count == 4)
    await cancelAndWait(detail)

    let single = Task { await model.detailAppeared(ids: ["p2"], index: 0, origin: nil) }
    await waitUntil { Self.loadedIDs(model) == ["p2"] }
    await cancelAndWait(single)
  }

  @Test("닫으면 읽기를 모두 취소하고 이미지를 모두 놓는다")
  func closeReleasesEverything() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoLibrary = Self.library(loadGate: { id in
      if id == "p1" {
        await gates.pass(0)
      }
    })
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 0, origin: nil) }
    await waitUntil { gates.hasEntered(0) && model.detailImages["p0"]?.image != nil }

    await cancelAndWait(detail)
    #expect(model.detailImages.isEmpty)

    // 늦게 끝난 읽기도 남지 않는다.
    gates.open(0)
    await settle()
    #expect(model.detailImages.isEmpty)
  }

  @Test("닫자마자 다시 열어도 지난 수명의 정리가 새 상세의 이미지를 지우지 않는다", arguments: [true, false])
  func reopenKeepsNewDetail(newStartsFirst: Bool) async {
    let photoLibrary = Self.library()
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let first = Task { await model.detailAppeared(ids: ["p0", "p1"], index: 0, origin: nil) }
    await waitUntil { Self.loadedIDs(model) == ["p0", "p1"] }

    let second: Task<Void, Never>
    if newStartsFirst {
      // 새 상세가 먼저 시작하고 지난 상세의 정리가 뒤에 돈다.
      second = Task { await model.detailAppeared(ids: ["p3", "p4"], index: 1, origin: nil) }
      await waitUntil { Self.loadedIDs(model) == ["p3", "p4"] }
      await cancelAndWait(first)
    } else {
      await cancelAndWait(first)
      second = Task { await model.detailAppeared(ids: ["p3", "p4"], index: 1, origin: nil) }
      await waitUntil { Self.loadedIDs(model) == ["p3", "p4"] }
    }
    await settle()
    #expect(Self.loadedIDs(model) == ["p3", "p4"])

    // 새 상세에서 넘기면 받아들인다.
    model.detailPageChanged(index: 0, id: "p3")
    #expect(Self.loadedIDs(model) == ["p3", "p4"])

    await cancelAndWait(second)
    #expect(model.detailImages.isEmpty)
  }

  @Test("수명 밖, 범위 밖 위치, 위치의 식별자가 지금 스냅숏과 다른 넘김은 무시한다")
  func ignoresInvalidPageChanges() async {
    let photoLibrary = Self.library()
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)

    model.detailPageChanged(index: 1, id: "p1")
    await settle()
    #expect(photoLibrary.loadImageRequests.isEmpty)

    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 2, origin: nil) }
    await waitUntil { Self.loadedIDs(model) == ["p1", "p2", "p3"] }

    model.detailPageChanged(index: 5, id: "p5")
    model.detailPageChanged(index: -1, id: "p0")
    // 다른 스냅숏의 상세가 보낸 늦은 이벤트.
    model.detailPageChanged(index: 0, id: "other")
    await settle()
    #expect(Self.loadedIDs(model) == ["p1", "p2", "p3"])
    #expect(photoLibrary.loadImageRequests.count == 3)

    await cancelAndWait(detail)
    model.detailPageChanged(index: 0, id: "p0")
    await settle()
    #expect(model.detailImages.isEmpty)
    #expect(photoLibrary.loadImageRequests.count == 3)
  }

  @Test("볼 수 없는 장은 창 안에 있는 동안 다시 읽지 않고, 창 밖으로 나갔다 오면 다시 읽는다")
  func unavailablePageIsReloadedAfterLeavingWindow() async {
    var results = Self.results
    results["p1"] = .failure(.failed)
    let photoLibrary = PhotoLibraryClientFake(loadImageResults: results)
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 1, origin: nil) }
    await waitUntil { model.detailImages["p1"]?.unavailableReason == .failed && Self.loadedIDs(model).count == 3 }

    model.detailPageChanged(index: 2, id: "p2")
    await waitUntil { model.detailImages["p3"] != nil }
    #expect(Self.requestCount(of: "p1", in: photoLibrary) == 1)

    model.detailPageChanged(index: 3, id: "p3")
    await waitUntil { model.detailImages["p4"] != nil }
    #expect(model.detailImages["p1"] == nil)

    model.detailPageChanged(index: 2, id: "p2")
    await waitUntil { model.detailImages["p1"]?.unavailableReason == .failed }
    #expect(Self.requestCount(of: "p1", in: photoLibrary) == 2)

    await cancelAndWait(detail)
  }

  /// "디코딩 중 취소돼 값이 늦게 옴"은 Fake 가 취소 뒤 늘 `.cancelled` 를 던져 직접 흉내 낼 수 없다.
  /// 대신 같은 장이 창 밖으로 나갔다 들어와 새 읽기가 먼저 끝난 뒤 지난 읽기가 끝나도 새 값이 남는지 본다.
  @Test("창 밖으로 나갔다 다시 들어온 장은 새 읽기 값이 남고, 지난 읽기가 늦게 끝나도 지우지 않는다")
  func reenteredPageKeepsNewLoad() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let counter = CallCounter()
    let photoLibrary = Self.library(loadGate: { id in
      if id == "p3" {
        await gates.pass(counter.next())
      }
    })
    let model = CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 2, origin: nil) }
    await waitUntil { gates.hasEntered(0) }

    model.detailPageChanged(index: 1, id: "p1")
    model.detailPageChanged(index: 2, id: "p2")
    await waitUntil { model.detailImages["p3"]?.image != nil }
    #expect(Self.requestCount(of: "p3", in: photoLibrary) == 2)

    gates.open(0)
    await settle()
    #expect(model.detailImages["p3"]?.image != nil)
    #expect(Self.loadedIDs(model) == ["p1", "p2", "p3"])

    await cancelAndWait(detail)
  }

  // MARK: - Helpers

  static var results: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] {
    Dictionary(uniqueKeysWithValues: self.ids.map { ($0, .success(.stub())) })
  }

  static func library(loadGate: (@Sendable (ImageAsset.ID) async -> Void)? = nil) -> PhotoLibraryClientFake {
    PhotoLibraryClientFake(loadImageResults: self.results, loadGate: loadGate)
  }

  /// 상태가 있는(읽음·볼 수 없음) 장의 식별자. 정렬해 비교한다.
  static func loadedIDs(_ model: CategoryModel) -> [ImageAsset.ID] {
    model.detailImages.keys.sorted()
  }

  static func requestCount(of id: ImageAsset.ID, in photoLibrary: PhotoLibraryClientFake) -> Int {
    photoLibrary.loadImageRequests.count(where: { $0.id == id })
  }
}
