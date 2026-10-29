import Foundation
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import Testing
import TripPlaceTesting
@testable import LibraryFeature

/// 보관함 화면이 여행 장소 이름 미리 받기 회차를 언제 시작·멈추는지와 캐시 쓰기 신호 (docs/ARCHITECTURE.md §4 위치·지도 원칙 ①).
@MainActor
struct LibraryModelPlacePrefetchTests {
  private static let classifying = IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 0)
  private static let finished = IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0)
  private static let recognizing = IndexingProgress(
    totalCount: 2,
    indexedCount: 2,
    skippedCount: 0,
    pendingTextCount: 2
  )
  private static let recognizingNext = IndexingProgress(
    totalCount: 2,
    indexedCount: 2,
    skippedCount: 0,
    pendingTextCount: 1,
    recognizedTextCount: 1
  )

  private static func model(
    indexing: IndexingClientFake,
    tripPlace: TripPlaceClientFake?,
    locale: LocaleBox = LocaleBox(Locale(identifier: "ko_KR"))
  ) -> LibraryModel {
    LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: indexing,
      photoStore: nil,
      notification: nil,
      widgetTimeline: nil,
      tripPlace: tripPlace,
      locale: { locale.value }
    )
  }

  /// 인덱싱 구독과 미리 받기 루프(캐시 쓰기 구독)가 선 뒤에 돌아온다.
  private static func appear(
    _ model: LibraryModel,
    indexing: IndexingClientFake,
    tripPlace: TripPlaceClientFake
  ) async -> Task<Void, Never> {
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 && tripPlace.activeSubscriberCount == 1 }
    return appear
  }

  @Test("1단계를 마친 진행률이 오면 글자 읽기 중에도 회차를 시작하고, 분류 중 진행률만으로는 시작하지 않는다")
  func classifiedProgressStartsRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.classifying)
    await waitUntil { model.indexingProgress == Self.classifying }
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.isEmpty)

    indexing.sendProgress(Self.recognizing)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers == ["ko_KR"] }
    await cancelAndWait(appear)
  }

  @Test("글자 읽기 중 배치마다 오는 진행률은 회차를 다시 시작하지 않고, 1·2단계를 모두 마치면 한 회차를 더 돈다")
  func recognizingBatchesDoNotRestartRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.recognizing)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    indexing.sendProgress(Self.recognizingNext)
    await waitUntil { model.indexingProgress == Self.recognizingNext }
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 1)

    indexing.sendProgress(Self.finished)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 2 }
    await cancelAndWait(appear)
  }

  @Test("앱 복귀·로캘 변경은 1단계를 마친 뒤에만 회차를 시작한다")
  func sceneAndLocaleTriggersAfterClassified() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    // 1단계를 마치기 전 계기는 버린다.
    model.sceneBecameActive()
    model.localeChanged()
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.isEmpty)

    // 글자 읽기 중에도 복귀·로캘 계기는 회차를 시작한다.
    indexing.sendProgress(Self.recognizing)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 1)

    model.sceneBecameActive()
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 2 }
    model.localeChanged()
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 3 }
    await cancelAndWait(appear)
  }

  @Test("회차가 도는 중 인덱싱이 다시 돌면(분류 중 진행률) 그 회차를 취소한다")
  func indexingRestartCancelsRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { _ in try? await Task.sleep(for: .seconds(3600)) })
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.finished)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    #expect(tripPlace.cancelledPrefetchCount == 0)

    indexing.sendProgress(Self.classifying)
    await waitUntil { tripPlace.cancelledPrefetchCount == 1 }
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 1)
    await cancelAndWait(appear)
  }

  @Test("회차가 도는 중 글자 읽기 진행률이 와도 그 회차를 취소하지 않는다")
  func recognizingProgressKeepsRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { _ in try? await Task.sleep(for: .seconds(3600)) })
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.recognizing)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    indexing.sendProgress(Self.recognizingNext)
    await waitUntil { model.indexingProgress == Self.recognizingNext }
    await settle()
    #expect(tripPlace.cancelledPrefetchCount == 0)
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 1)
    await cancelAndWait(appear)
  }

  @Test("글자 읽기 중 화면을 나갔다 다시 들어오면 처음 오는 글자 읽기 진행률이 회차를 다시 시작한다")
  func reappearDuringRecognizingRestartsRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { _ in try? await Task.sleep(for: .seconds(3600)) })
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let first = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.recognizing)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    await cancelAndWait(first)
    await waitUntil { indexing.activeRunCount == 0 && tripPlace.activeSubscriberCount == 0 }
    #expect(tripPlace.cancelledPrefetchCount == 1)

    let second = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)
    indexing.sendProgress(Self.recognizingNext)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 2 }
    await cancelAndWait(second)
  }

  @Test("회차가 도는 중 온 계기 여러 개는 끝난 뒤 한 회차로 합친다")
  func triggersDuringRoundCoalesce() async {
    let gates = CallGates(holding: [0])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { await gates.pass($0) })
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.finished)
    await waitUntil { gates.hasEntered(0) }
    model.sceneBecameActive()
    indexing.sendProgress(Self.finished)
    model.sceneBecameActive()
    await waitUntil { model.storeRevision == 2 }
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 1)

    gates.open(0)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 2 }
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 2)
    await cancelAndWait(appear)
  }

  @Test("미리 받기가 캐시에 쓰면 placeRevision 만 오르고 storeRevision 은 그대로다")
  func placeChangeBumpsPlaceRevisionOnly() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake()
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)
    let storeRevision = model.storeRevision

    tripPlace.sendPlaceChange()
    await waitUntil { model.placeRevision == 1 }
    tripPlace.sendPlaceChange()
    await waitUntil { model.placeRevision == 2 }
    #expect(model.storeRevision == storeRevision)
    await cancelAndWait(appear)
  }

  @Test("회차가 도는 중 로캘이 바뀌면 그 회차를 취소하고 새 로캘로 한 회차를 돈다")
  func localeChangeDuringRoundRestartsWithNewLocale() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { index in
      if index == 0 {
        try? await Task.sleep(for: .seconds(3600))
      }
    })
    let locale = LocaleBox(Locale(identifier: "ko_KR"))
    let model = Self.model(indexing: indexing, tripPlace: tripPlace, locale: locale)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.finished)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers == ["ko_KR"] }

    locale.value = Locale(identifier: "en_US")
    model.localeChanged()
    await waitUntil { tripPlace.prefetchLocaleIdentifiers == ["ko_KR", "en_US"] }
    #expect(tripPlace.cancelledPrefetchCount == 1)
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 2)
    await cancelAndWait(appear)
  }

  @Test("화면이 사라지면 도는 회차를 취소하고 캐시 쓰기 구독을 끝낸다")
  func disappearCancelsRound() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let tripPlace = TripPlaceClientFake(onPrefetch: { _ in try? await Task.sleep(for: .seconds(3600)) })
    let model = Self.model(indexing: indexing, tripPlace: tripPlace)
    let appear = await Self.appear(model, indexing: indexing, tripPlace: tripPlace)

    indexing.sendProgress(Self.finished)
    await waitUntil { tripPlace.prefetchLocaleIdentifiers.count == 1 }
    await cancelAndWait(appear)
    #expect(tripPlace.cancelledPrefetchCount == 1)
    await waitUntil { tripPlace.activeSubscriberCount == 0 }

    // 사라진 뒤의 계기는 버린다.
    model.sceneBecameActive()
    await settle()
    #expect(tripPlace.prefetchLocaleIdentifiers.count == 1)
  }

  @Test("미리 받기가 없으면(저장소 없음) 계기가 와도 아무 일 없다")
  func withoutTripPlaceDoesNothing() async {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = Self.model(indexing: indexing, tripPlace: nil)
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }

    indexing.sendProgress(Self.finished)
    await waitUntil { model.indexingProgress == Self.finished }
    model.sceneBecameActive()
    model.localeChanged()
    await settle()
    #expect(model.placeRevision == 0)
    await cancelAndWait(appear)
  }
}
