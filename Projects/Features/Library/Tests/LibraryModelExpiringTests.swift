import Core
import Foundation
import IndexingInterface
import IndexingTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 보관함 홈 곧 만료 띠(`LibraryModel.expiringGifticons`, docs/ARCHITECTURE.md §4 카테고리 화면).
/// 지금은 Asia/Seoul 2026-10-19 08:00 이라 창은 10-19 ~ 10-26 이다. 알림은 nil 로 만들어 알림 동기화와 독립임을 보인다.
/// 보관함 변경 관찰이 이어지는 동안 띠 루프도 이어지므로(이 준비는 관찰을 끝내지 않는다), 결과를 확인한 뒤 Task 를 취소해 끝낸다. 늦은 결과·합침·위젯과 같음·상한은
/// `LibraryModelExpiringLoopTests`.
@MainActor
struct LibraryModelExpiringTests {
  @Test("첫 읽기는 창 안 미사용 기프티콘을 만료일 오름차순으로 담고 창 밖·사용함은 뺀다")
  func firstReadBuildsStrip() async {
    let photoStore = PhotoStoreClientFake(
      images: [
        .gifticon(id: "later", expiryDate: .date(2026, 10, 26)),
        .gifticon(id: "today", expiryDate: .date(2026, 10, 19)),
        .gifticon(id: "soon", expiryDate: .date(2026, 10, 20)),
        .gifticon(id: "outside", expiryDate: .date(2026, 10, 27)),
        .gifticon(id: "yesterday", expiryDate: .date(2026, 10, 18)),
        .gifticon(id: "used", expiryDate: .date(2026, 10, 21)),
        .pendingGifticon(id: "pending"),
      ],
      usedIDs: ["used"]
    )
    let model = Self.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }

    await waitUntil { model.expiringGifticons != nil }

    #expect(model.expiringGifticons?.items.map(\.id) == ["today", "soon", "later"])
    #expect(model.expiringGifticons?.count == 3)
    #expect(model.expiringGifticons?.today == .date(2026, 10, 19))
    let dues: [GifticonDue] = [.remaining(days: 0), .remaining(days: 1), .remaining(days: 7)]
    #expect(model.expiringGifticons?.items.map(\.due) == dues)
    #expect(model.expiringThumbnailIDs == ["today", "soon", "later"])
    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 띠가 없다")
  func noStoreHasNoStrip() async {
    let now = GifticonFixture.now
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: nil,
      photoStore: nil,
      notification: nil,
      widgetTimeline: nil,
      tripPlace: nil,
      backgroundIndexing: nil,
      calendar: .seoul,
      now: { now }
    )
    model.sceneBecameActive()
    let appear = Task { await model.onAppear() }
    await settle()

    #expect(model.expiringGifticons == nil)
    #expect(model.expiringThumbnailIDs.isEmpty)
    await cancelAndWait(appear)
  }

  @Test("처음 읽기에 실패하면 띠가 없고, 다음 진행률 뒤 다시 읽어 보인다")
  func firstFailureHidesUntilNextRead() async {
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))],
      gifticonsErrors: [0: .failed]
    )
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = Self.model(photoStore: photoStore, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { photoStore.gifticonsCallCount == 1 && indexing.activeRunCount == 1 }
    await settle()
    #expect(model.expiringGifticons == nil)

    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { model.expiringGifticons != nil }

    #expect(model.expiringGifticons?.items.map(\.id) == ["a"])
    await cancelAndWait(appear)
  }

  @Test("다시 읽기에 실패하면 지난 띠를 그대로 둔다")
  func rereadFailureKeepsLastValue() async throws {
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))],
      gifticonsErrors: [1: .failed]
    )
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = Self.model(photoStore: photoStore, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil && indexing.activeRunCount == 1 }

    try await photoStore.save([.gifticon(id: "b", expiryDate: .date(2026, 10, 21))])
    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { photoStore.gifticonsCallCount == 2 }
    await settle()
    #expect(model.expiringGifticons?.items.map(\.id) == ["a"])

    // 다음 계기에는 다시 읽어 맞춘다.
    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { model.expiringGifticons?.count == 2 }
    #expect(model.expiringGifticons?.items.map(\.id) == ["a", "b"])
    await cancelAndWait(appear)
  }

  @Test("인덱싱 진행률과 멈춤마다 다시 읽어 새 기프티콘을 반영한다")
  func progressAndStopReread() async throws {
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))])
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = Self.model(photoStore: photoStore, indexing: indexing)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil && indexing.activeRunCount == 1 }

    try await photoStore.save([.gifticon(id: "b", expiryDate: .date(2026, 10, 19))])
    indexing.sendProgress(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    await waitUntil { model.expiringGifticons?.items.map(\.id) == ["b", "a"] }

    try await photoStore.save([.gifticon(id: "c", expiryDate: .date(2026, 10, 22))])
    indexing.finishRuns()
    await waitUntil { model.expiringGifticons?.items.map(\.id) == ["b", "a", "c"] }
    #expect(model.isIndexingStopped)
    await cancelAndWait(appear)
  }

  @Test("사용함으로 바꾼 뒤 사용 여부 변경을 알리면 그 칩이 빠지고 개수가 준다")
  func usageChangeRemovesChip() async throws {
    let photoStore = PhotoStoreClientFake(images: [
      .gifticon(id: "a", expiryDate: .date(2026, 10, 20)),
      .gifticon(id: "b", expiryDate: .date(2026, 10, 21)),
    ])
    let model = Self.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons?.count == 2 }

    _ = try await photoStore.setGifticonUsed(true, id: "a")
    model.gifticonUsageChanged()
    await waitUntil { model.expiringGifticons?.count == 1 }

    #expect(model.expiringGifticons?.items.map(\.id) == ["b"])
    #expect(model.expiringThumbnailIDs == ["b"])
    await cancelAndWait(appear)
  }

  @Test("앱이 뒤에 있을 때의 날짜 변경은 무시한다")
  func dayChangeInBackgroundIsIgnored() async {
    let clock = TestClock(now: GifticonFixture.now, calendar: .seoul)
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "today", expiryDate: .date(2026, 10, 19))])
    let model = Self.model(photoStore: photoStore, clock: clock)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil }

    model.sceneEnteredBackground()
    clock.now = .seoul(2026, 10, 20, hour: 0, minute: 1)
    model.dayChanged()
    await settle()

    #expect(model.expiringGifticons?.today == .date(2026, 10, 19))
    #expect(model.expiringGifticons?.items.map(\.id) == ["today"])
    #expect(photoStore.gifticonsCallCount == 1)
    await cancelAndWait(appear)
  }

  @Test("날짜가 바뀌면 다시 읽지 않고 오늘을 다시 계산한다: 어제 만료가 빠지고 새 +7 일이 든다")
  func dayChangeDoesNotRead() async {
    let clock = TestClock(now: GifticonFixture.now, calendar: .seoul)
    let photoStore = PhotoStoreClientFake(images: [
      .gifticon(id: "today", expiryDate: .date(2026, 10, 19)),
      .gifticon(id: "eighth", expiryDate: .date(2026, 10, 27)),
    ])
    let model = Self.model(photoStore: photoStore, clock: clock)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil }

    clock.now = .seoul(2026, 10, 20, hour: 0, minute: 1)
    model.dayChanged()
    await settle()

    #expect(model.expiringGifticons?.today == .date(2026, 10, 20))
    #expect(model.expiringGifticons?.items.map(\.id) == ["eighth"])
    #expect(model.expiringGifticons?.items.map(\.due) == [.remaining(days: 7)])
    #expect(photoStore.gifticonsCallCount == 1)
    await cancelAndWait(appear)
  }

  @Test("앱이 앞으로 오면 오늘을 다시 계산하고 다시 읽는다. 읽기에 실패해도 날짜는 바뀐다")
  func sceneActiveRecomputesAndRereads() async {
    let clock = TestClock(now: GifticonFixture.now, calendar: .seoul)
    let photoStore = PhotoStoreClientFake(
      images: [
        .gifticon(id: "today", expiryDate: .date(2026, 10, 19)),
        .gifticon(id: "eighth", expiryDate: .date(2026, 10, 27)),
      ],
      gifticonsErrors: [1: .failed]
    )
    let model = Self.model(photoStore: photoStore, clock: clock)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil }

    model.sceneEnteredBackground()
    clock.now = .seoul(2026, 10, 20, hour: 9)
    model.sceneBecameActive()
    await waitUntil { photoStore.gifticonsCallCount == 2 }
    await settle()

    #expect(model.expiringGifticons?.today == .date(2026, 10, 20))
    #expect(model.expiringGifticons?.items.map(\.id) == ["eighth"])
    await cancelAndWait(appear)
  }

  // MARK: - Helpers

  /// 알림·위젯 없이 만든다. `activates` 면 화면 진입 전에 앞으로 온다(앞에서 켤 때의 순서).
  /// `photoLibrary` 는 보관함 변경 관찰을 끝내 보려는 테스트가 넘긴다.
  static func model(
    photoStore: PhotoStoreClientFake,
    photoLibrary: PhotoLibraryClientFake = PhotoLibraryClientFake(currentState: .authorized),
    indexing: IndexingClientFake? = nil,
    clock: TestClock = TestClock(now: GifticonFixture.now, calendar: .seoul),
    activates: Bool = true
  ) -> LibraryModel {
    let model = LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: photoStore,
      notification: nil,
      widgetTimeline: nil,
      tripPlace: nil,
      backgroundIndexing: nil,
      calendar: .seoul,
      now: { clock.now }
    )
    if activates {
      model.sceneBecameActive()
    }
    return model
  }
}
