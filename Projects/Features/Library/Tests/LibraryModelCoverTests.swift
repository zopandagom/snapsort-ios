import Core
import Foundation
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 보관함 카드 대표 사진 식별자(`LibraryModel.coverIDs`)는 개수와 같은 읽기·같은 세대로 바뀐다 (docs/ARCHITECTURE.md §4 카테고리 화면).
@MainActor
struct LibraryModelCoverTests {
  @Test("화면 진입 시 개수와 대표를 함께 읽는다")
  func onAppearLoadsCountsAndCovers() async {
    let photoStore = PhotoStoreClientFake(
      images: [
        .taken(id: "a", categories: [.food], day: 2),
        .taken(id: "b", categories: [.food], day: 1),
        .taken(id: "c", categories: [.landscape], day: 0),
      ],
      trips: [.covering(["c"])]
    )
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = libraryModel(photoLibrary, photoStore: photoStore)
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(model.categoryCounts == [.food: 2, .landscape: 1, .travel: 1])
    #expect(model.coverIDs == [.food: ["a", "b"], .landscape: ["c"], .travel: ["c"]])
  }

  @Test("진행률마다 대표를 다시 읽는다")
  func progressRefreshesCovers() async {
    let photoStore = PhotoStoreClientFake(images: [.taken(id: "a", categories: [.food], day: 0)])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = libraryModel(photoLibrary, indexing: indexing, photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    #expect(model.coverIDs == [.food: ["a"]])

    // 인덱서가 더 새 사진을 저장하고 진행률을 보낸 것처럼 흉내 낸다.
    try? await photoStore.save([.taken(id: "b", categories: [.food], day: 1)])
    indexing.sendProgress(IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0))
    await waitUntil { model.coverIDs == [.food: ["b", "a"]] }

    await cancelAndWait(appear)
  }

  @Test("대표 읽기가 실패하면 개수와 대표 모두 지난 값을 둔다")
  func coverFailureKeepsCountsAndCovers() async {
    let photoStore = PhotoStoreClientFake(
      images: [.taken(id: "a", categories: [.food], day: 0)],
      categoryCoversErrors: [1: .failed]
    )
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = libraryModel(photoLibrary, indexing: indexing, photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }

    // 그사이 저장소 개수가 바뀌었지만 대표 읽기가 실패해 개수도 지난 값을 둔다.
    try? await photoStore.save([.taken(id: "b", categories: [.food], day: 1)])
    let progress = IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0)
    indexing.sendProgress(progress)
    await waitUntil { photoStore.categoryCoversCallCount == 2 }
    await settle()
    #expect(model.categoryCounts == [.food: 1])
    #expect(model.coverIDs == [.food: ["a"]])

    // 다음 읽기가 성공하면 둘 다 함께 바뀐다.
    indexing.sendProgress(progress)
    await waitUntil { model.categoryCounts == [.food: 2] }
    #expect(model.coverIDs == [.food: ["b", "a"]])

    await cancelAndWait(appear)
  }

  @Test("지난 진입의 늦은 개수·대표 결과는 새 진입 상태를 덮지 않는다")
  func lateResultOfPreviousEntryIsDropped() async {
    // 첫 진입의 대표 읽기를 붙잡고, 취소돼도 열 때까지 기다리게 해 다시 진입한 뒤에 끝나게 한다.
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [.taken(id: "a", categories: [.food], day: 0)],
      onCategoryCovers: { index in await gates.pass(index) }
    )
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = libraryModel(photoLibrary, photoStore: photoStore)
    let first = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }

    // 화면을 나갔다 바로 들어온다. 그사이 저장소가 바뀌어 새 진입은 두 장을 읽는다.
    first.cancel()
    try? await photoStore.save([.taken(id: "b", categories: [.food], day: 1)])
    let second = Task { await model.onAppear() }
    await waitUntil { model.coverIDs == [.food: ["b", "a"]] }

    // 지난 진입의 읽기(한 장)가 늦게 끝나도 덮지 않는다.
    gates.open(0)
    await first.value
    await settle()
    #expect(model.categoryCounts == [.food: 2])
    #expect(model.coverIDs == [.food: ["b", "a"]])

    await cancelAndWait(second)
  }

  @Test("대표 수는 카테고리마다 coverLimit 을 넘지 않는다")
  func coversAreLimitedPerCategory() async {
    let images = (0 ..< 6).map { IndexedImage.taken(id: "food-\($0)", categories: [.food], day: $0) }
    let trips = (0 ..< 6).map { Trip.covering(["food-\($0)"], day: $0) }
    let photoStore = PhotoStoreClientFake(images: images, trips: trips)
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = libraryModel(photoLibrary, photoStore: photoStore)
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(LibraryModel.coverLimit == 4)
    #expect(model.categoryCounts[.food] == 6)
    #expect(model.coverIDs[.food] == ["food-5", "food-4", "food-3", "food-2"])
    #expect(model.coverIDs[.travel]?.count == LibraryModel.coverLimit)
  }
}

extension IndexedImage {
  /// 기준 시각에서 `day` 일 뒤에 찍은 이미지. 클수록 최신이다.
  static func taken(id: String, categories: Set<ImageCategory>, day: Int) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: Date(timeIntervalSince1970: Double(day) * 86400)),
      labels: [],
      textRecognition: .notNeeded,
      categories: categories
    )
  }
}

extension Trip {
  /// 그 사진들로 된 여행. `day` 가 클수록 최근 여행이다.
  static func covering(_ assetIDs: [String], day: Int = 0) -> Trip {
    let date = Date(timeIntervalSince1970: Double(day) * 86400)
    return Trip(assetIDs: assetIDs, startDate: date, endDate: date, center: Coordinate(latitude: 0, longitude: 0))
  }
}
