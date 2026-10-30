import BackgroundIndexingTesting
import Foundation
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import Testing
import TripPlaceTesting
@testable import LibraryFeature

/// 앱이 뒤로 가고 앞으로 올 때 보관함 화면이 BG 작업에 알리는 것과, 뒤에 있는 동안의 장소 캐시 쓰기 (docs/ARCHITECTURE.md §4 인덱싱).
@MainActor
struct LibraryModelBackgroundTests {
  private static let finished = IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0)

  private static func model(
    indexing: IndexingClientFake,
    tripPlace: TripPlaceClientFake,
    backgroundIndexing: BackgroundIndexingClientFake
  ) -> LibraryModel {
    LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: indexing,
      photoStore: nil,
      notification: nil,
      widgetTimeline: nil,
      tripPlace: tripPlace,
      backgroundIndexing: backgroundIndexing,
      locale: { Locale(identifier: "ko_KR") }
    )
  }

  /// 앱이 앞으로 온 뒤(BG 작업에 `.didBecomeActive` 를 알린다) 화면 진입을 시작하고,
  /// 인덱싱 구독과 미리 받기 루프(캐시 쓰기 구독)가 선 뒤에 돌아온다.
  private static func appear(
    _ model: LibraryModel,
    indexing: IndexingClientFake,
    tripPlace: TripPlaceClientFake
  ) async -> Task<Void, Never> {
    model.sceneBecameActive()
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 && tripPlace.activeSubscriberCount == 1 }
    return appear
  }

  @Test("뒤로 가면 BG 작업에 알리고, 분류 구독을 끊지 않아 멈춤 안내가 없다")
  func enteringBackgroundKeepsIndexing() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace, backgroundIndexing: backgroundIndexing)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    model.sceneEnteredBackground()
    await settle()

    #expect(backgroundIndexing.events == [.didBecomeActive, .didEnterBackground])
    #expect(indexing.activeRunCount == 1)
    #expect(!model.isIndexingStopped)
    await cancelAndWait(appear)
  }

  @Test("뒤에 있는 동안의 장소 캐시 쓰기는 앞으로 올 때 한 번만 알린다")
  func placeChangesWaitUntilActive() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace, backgroundIndexing: backgroundIndexing)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    model.sceneEnteredBackground()
    tripPlace.sendPlaceChange()
    await settle()
    tripPlace.sendPlaceChange()
    await settle()
    #expect(model.placeRevision == 0)

    model.sceneBecameActive()
    #expect(model.placeRevision == 1)
    #expect(backgroundIndexing.events == [.didBecomeActive, .didEnterBackground, .didBecomeActive])

    // 앞에 있으면 지금처럼 바로 알린다.
    tripPlace.sendPlaceChange()
    await waitUntil { model.placeRevision == 2 }
    await cancelAndWait(appear)
  }

  @Test("뒤로 가면 도는 미리 받기 회차를 취소한다")
  func enteringBackgroundCancelsRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { _ in try? await Task.sleep(for: .seconds(3600)) })
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace, backgroundIndexing: backgroundIndexing)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.finished)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    #expect(tripPlace.cancelledPrefetchCount == 0)

    model.sceneEnteredBackground()
    await waitUntil { tripPlace.cancelledPrefetchCount == 1 }
    await cancelAndWait(appear)
  }

  @Test("앞으로 오면 BG 작업에 알리고, 그 뒤 온 진행률로 저장소를 다시 읽는다")
  func becomingActiveResumesAndReloads() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace, backgroundIndexing: backgroundIndexing)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    model.sceneEnteredBackground()
    model.sceneBecameActive()
    #expect(backgroundIndexing.events == [.didBecomeActive, .didEnterBackground, .didBecomeActive])

    let revision = model.storeRevision
    indexing.sendProgress(Self.finished)
    await waitUntil { model.storeRevision == revision + 1 }
    #expect(!model.isIndexingStopped)
    await cancelAndWait(appear)
  }

  @Test("처음 값이 앞(뒤로 간 적 없음)이면 BG 작업에 알리기만 하고 장소 화면을 다시 읽게 하지 않는다")
  func initialActiveOnly() {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace, backgroundIndexing: backgroundIndexing)

    model.sceneBecameActive()

    #expect(backgroundIndexing.events == [.didBecomeActive])
    #expect(model.placeRevision == 0)
  }
}
