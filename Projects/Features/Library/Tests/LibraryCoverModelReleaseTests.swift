import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 보관함 카드 대표 썸네일의 보관 규칙: 대표 집합 안의 것만 보관하고, 늦은 결과·지난 로더가 상태를 바꾸지 않는다.
@MainActor
struct LibraryCoverModelReleaseTests {
  @Test("대표 집합 밖 식별자의 카드 이벤트는 읽지도 보관하지도 않는다")
  func cardEventOutsideCoversIsIgnored() async {
    // 대체 상태가 된 뒤 대표에서 빠진 식별자다. 집합 안이었다면 카드 이벤트가 다시 읽었을 것이다.
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: ["x": .failure(.notAvailableLocally), "a": .success(.stub())]
    )
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["x", "a"]])
    await waitUntil {
      model.thumbnails["x"]?.unavailableReason == .inCloudOnly && model.thumbnails["a"]?.image != nil
    }

    model.coversChanged([.food: ["a"]])
    model.cardAppeared(ids: ["x", "a"])
    await settle()

    #expect(model.thumbnails["x"] == nil)
    #expect(photoLibrary.requestCount("x") == 1)
    #expect(photoLibrary.requestCount("a") == 1)
    await cancelAndWait(loader)
  }

  @Test("대표에서 빠진 썸네일은 놓는다")
  func removedCoverIsReleased() async {
    let photoLibrary = coverLibrary(["a", "b"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["a", "b"]])
    await waitUntil { model.thumbnails.count == 2 }

    model.coversChanged([.food: ["b"]])

    #expect(model.thumbnails["a"] == nil)
    #expect(model.thumbnails["b"]?.image != nil)
    await cancelAndWait(loader)
  }

  @Test("대표에서 빠진 뒤 늦게 끝난 읽기는 되살리지 않는다")
  func lateLoadOfRemovedCoverIsDropped() async {
    let gates = LoadGates(holding: [LoadGates.Key("a", 0)])
    defer { gates.openAll() }
    let photoLibrary = coverLibrary(["a", "b"], gates: gates)
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["a"]])
    await waitUntil { gates.enteredCount("a") == 1 }

    model.coversChanged([.food: ["b"]])
    await waitUntil { model.thumbnails["b"]?.image != nil }
    gates.open(LoadGates.Key("a", 0))
    await waitUntil { gates.passedCount("a") == 1 }
    await settle()

    #expect(model.thumbnails["a"] == nil)
    await cancelAndWait(loader)
  }

  @Test("빠졌다 다시 든 이미지는 지난 읽기 결과를 버리고 새 결과를 쓴다")
  func readdedCoverUsesNewLoad() async {
    let gates = LoadGates(holding: [LoadGates.Key("a", 0), LoadGates.Key("a", 1)])
    defer { gates.openAll() }
    let photoLibrary = coverLibrary(["a"], gates: gates)
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)
    model.coversChanged([.food: ["a"]])
    await waitUntil { gates.enteredCount("a") == 1 }
    model.coversChanged([:])
    model.coversChanged([.food: ["a"]])
    await waitUntil { gates.enteredCount("a") == 2 }

    // 지난 읽기만 끝난다. 번호가 맞지 않아 버려지고 새 읽기를 기다린다.
    gates.open(LoadGates.Key("a", 0))
    await waitUntil { gates.passedCount("a") == 1 }
    await settle()
    #expect(model.thumbnails["a"] == nil)

    gates.open(LoadGates.Key("a", 1))
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(loader)
  }

  @Test("화면이 사라져 로더가 취소되면 읽은 것은 남기고 읽던 것은 다음 진입에서 다시 읽는다")
  func cancelledLoaderKeepsLoadedAndReloadsPending() async {
    let gates = LoadGates(holding: [LoadGates.Key("b", 0)])
    defer { gates.openAll() }
    let photoLibrary = coverLibrary(["a", "b"], gates: gates)
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let first = await startLoader(model)
    model.coversChanged([.food: ["a", "b"]])
    await waitUntil { model.thumbnails["a"]?.image != nil && gates.enteredCount("b") == 1 }

    await cancelAndWait(first)
    #expect(model.thumbnails["a"]?.image != nil)
    #expect(model.thumbnails["b"] == nil)

    let second = await startLoader(model)
    await waitUntil { model.thumbnails["b"]?.image != nil }
    #expect(photoLibrary.requestCount("a") == 1)
    #expect(photoLibrary.requestCount("b") == 2)
    await cancelAndWait(second)
  }

  @Test("지난 로더가 늦게 끝나도 새 로더의 요청 통로를 지우지 않는다")
  func lateEndOfPreviousLoaderKeepsNewChannel() async {
    let photoLibrary = coverLibrary(["a"])
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let first = await startLoader(model)
    // 화면에 다시 들어와 새 로더가 시작된 뒤에 지난 로더의 취소가 닿는다.
    let second = await startLoader(model)
    await cancelAndWait(first)

    model.coversChanged([.food: ["a"]])
    await waitUntil { model.thumbnails["a"]?.image != nil }
    await cancelAndWait(second)
  }

  @Test("썸네일 수는 대표 집합 크기를 넘지 않는다")
  func thumbnailsStayWithinCoverSet() async {
    let categories = ImageCategory.allCases
    let covers = Dictionary(uniqueKeysWithValues: categories.map { category in
      (category, (0 ..< LibraryModel.coverLimit).map { "\(category.rawValue)-\($0)" })
    })
    let nextCovers = covers.mapValues { ids in ids.map { "\($0)-next" } }
    let outside = (0 ..< 10).map { "outside-\($0)" }
    let allIDs = Array(covers.values.joined()) + Array(nextCovers.values.joined()) + outside
    let photoLibrary = coverLibrary(allIDs)
    let model = LibraryCoverModel(photoLibrary: photoLibrary)
    let loader = await startLoader(model)

    model.coversChanged(covers)
    await waitUntil { model.thumbnails.count == 48 }
    model.cardAppeared(ids: outside)
    await settle()
    #expect(model.thumbnails.count == 48)
    #expect(outside.allSatisfy { photoLibrary.requestCount($0) == 0 })

    // 대표가 모두 바뀌면 지난 썸네일은 놓고 새 대표만 남는다.
    model.coversChanged(nextCovers)
    #expect(model.thumbnails.isEmpty)
    await waitUntil { model.thumbnails.count == 48 }
    #expect(Set(model.thumbnails.keys) == Set(nextCovers.values.joined()))
    await cancelAndWait(loader)
  }
}
