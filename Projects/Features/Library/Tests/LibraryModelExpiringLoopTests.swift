import Core
import Foundation
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 보관함 홈 곧 만료 띠의 읽기 루프: 늦은 결과 버림, 요청 합침, 위젯과 같은 개수, 상한, 개수 읽기와의 독립, 미룬 진입, 끝남(화면 진입의 다른 일이 모두 끝나면 루프도 끝난다).
/// 준비는 `LibraryModelExpiringTests.model` 과 같다(지금 Asia/Seoul 2026-10-19 08:00, 창 10-19 ~ 10-26).
@MainActor
struct LibraryModelExpiringLoopTests {
  @Test("화면을 나갔다 바로 들어와 지난 읽기가 늦게 끝나도 새 띠를 덮지 않는다")
  func staleReadIsDropped() async throws {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))],
      onGifticons: { await gates.pass($0) }
    )
    let model = LibraryModelExpiringTests.model(photoStore: photoStore)
    let first = Task { await model.onAppear() }
    // 지난 읽기가 "a" 하나를 읽은 채 붙잡힌다. 취소해도 풀리지 않는다.
    await waitUntil { gates.hasEntered(0) }
    first.cancel()

    try await photoStore.save([.gifticon(id: "b", expiryDate: .date(2026, 10, 21))])
    let second = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons?.items.map(\.id) == ["a", "b"] }

    gates.open(0)
    // 지난 읽기는 지난 진입의 Task 안에서 돌므로, 그 Task 가 끝나면 지난 읽기도 끝났다.
    await first.value

    #expect(model.expiringGifticons?.items.map(\.id) == ["a", "b"])
    await cancelAndWait(second)
  }

  @Test("읽는 중 들어온 요청 여러 개는 끝난 뒤 한 번으로 합친다")
  func coalescesRequestsDuringRead() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))],
      onGifticons: { await gates.pass($0) }
    )
    let model = LibraryModelExpiringTests.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil }

    model.gifticonUsageChanged()
    await waitUntil { gates.hasEntered(1) }
    model.gifticonUsageChanged()
    model.gifticonUsageChanged()
    model.gifticonUsageChanged()
    await settle()

    gates.open(1)
    await waitUntil { gates.hasEntered(2) }
    await settle()

    #expect(!gates.hasEntered(3))
    #expect(photoStore.gifticonsCallCount == 3)
    await cancelAndWait(appear)
  }

  @Test("같은 저장소 상태면 띠 개수가 위젯 오늘 요약 개수와 같다")
  func countMatchesWidgetToday() async throws {
    let photoStore = PhotoStoreClientFake(
      images: [
        .gifticon(id: "today", expiryDate: .date(2026, 10, 19)),
        .gifticon(id: "plus3", expiryDate: .date(2026, 10, 22)),
        .gifticon(id: "plus7", expiryDate: .date(2026, 10, 26)),
        .gifticon(id: "plus8", expiryDate: .date(2026, 10, 27)),
        .gifticon(id: "yesterday", expiryDate: .date(2026, 10, 18)),
        .gifticon(id: "unknown", expiryDate: nil),
        .gifticon(id: "used", expiryDate: .date(2026, 10, 20)),
        .pendingGifticon(id: "pending"),
      ],
      usedIDs: ["used"]
    )
    let model = LibraryModelExpiringTests.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil }

    let today = LocalDate.date(2026, 10, 19)
    let expiries = try await photoStore.upcomingGifticonExpiries(from: today)
    let widgetToday = ExpiryWidgetTimeline.summaries(for: expiries, isChecking: false, today: today).first

    #expect(model.expiringGifticons?.count == 3)
    #expect(model.expiringGifticons?.count == widgetToday?.count)
    await cancelAndWait(appear)
  }

  @Test("창 안이 상한보다 많으면 개수는 전체, 칩·썸네일 식별자는 상한까지다")
  func limitCapsThumbnails() async {
    let images: [IndexedImage] = (0 ..< 25).map { index in
      .gifticon(id: String(format: "g%02d", index), expiryDate: .date(2026, 10, 19 + index % 8))
    }
    let model = LibraryModelExpiringTests.model(photoStore: PhotoStoreClientFake(images: images))
    let appear = Task { await model.onAppear() }
    await waitUntil { model.expiringGifticons != nil }

    #expect(model.expiringGifticons?.count == 25)
    #expect(model.expiringGifticons?.items.count == LibraryModel.expiringLimit)
    #expect(model.expiringThumbnailIDs.count == 20)
    await cancelAndWait(appear)
  }

  @Test("띠 첫 읽기만 실패해도 카테고리 개수·대표는 채워진다")
  func stripFailureIsIndependentOfCounts() async {
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))],
      gifticonsErrors: [0: .failed]
    )
    let model = LibraryModelExpiringTests.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.categoryCounts[.gifticon] == 1 && photoStore.gifticonsCallCount == 1 }
    await settle()

    #expect(model.coverIDs[.gifticon] == ["a"])
    #expect(model.expiringGifticons == nil)
    await cancelAndWait(appear)
  }

  @Test("앞으로 오기 전 진입은 앞으로 올 때의 요청을 버리고 첫 진입 읽기 한 번으로 대신한다")
  func deferredEntryReadsOnce() async {
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))])
    let model = LibraryModelExpiringTests.model(photoStore: photoStore, activates: false)
    let appear = Task { await model.onAppear() }
    await settle()
    #expect(photoStore.gifticonsCallCount == 0)

    model.sceneBecameActive()
    await waitUntil { model.expiringGifticons != nil }
    await settle()

    #expect(photoStore.gifticonsCallCount == 1)
    await cancelAndWait(appear)
  }

  // MARK: - 끝남

  @Test("다른 일이 모두 끝나면 진입 읽기를 마친 뒤 띠 루프도 끝나 화면 진입이 돌아온다")
  func endsAfterOtherWorkFinishes() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    photoLibrary.finishImageChanges()
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))])
    let model = LibraryModelExpiringTests.model(photoStore: photoStore, photoLibrary: photoLibrary)

    await model.onAppear()

    #expect(model.expiringGifticons?.items.map(\.id) == ["a"])
    #expect(photoStore.gifticonsCallCount == 1)
  }

  @Test("끝난 뒤 온 사용 여부 변경 신호는 버리고 다음 진입이 읽는다")
  func signalAfterEndIsDropped() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    photoLibrary.finishImageChanges()
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))])
    let model = LibraryModelExpiringTests.model(photoStore: photoStore, photoLibrary: photoLibrary)
    await model.onAppear()

    model.gifticonUsageChanged()
    await settle()
    #expect(photoStore.gifticonsCallCount == 1)

    await model.onAppear()
    #expect(photoStore.gifticonsCallCount == 2)
  }

  @Test("끝나는 순간 읽는 중이던 읽기 결과는 반영하고, 그 뒤 온 신호는 버린다")
  func readInFlightAtEndIsKept() async {
    let gates = CallGates(holding: [0])
    defer { gates.open(0) }
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    photoLibrary.finishImageChanges()
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiryDate: .date(2026, 10, 20))],
      onGifticons: { await gates.pass($0) }
    )
    let model = LibraryModelExpiringTests.model(photoStore: photoStore, photoLibrary: photoLibrary)
    let appear = Task { await model.onAppear() }
    // 인덱서가 없어 개수를 읽으면 분류 일이 끝난다. 관찰도 끝났으므로 안쪽 그룹이 끝나 띠 통로가 닫힌다.
    await waitUntil { gates.hasEntered(0) && model.categoryCounts[.gifticon] == 1 }
    await settle()

    // 통로가 닫힌 뒤라 버려진다. 읽는 중에 통로를 닫지 않았다면 이 신호가 한 번 더 읽힌다.
    model.gifticonUsageChanged()
    gates.open(0)
    await appear.value

    #expect(model.expiringGifticons?.items.map(\.id) == ["a"])
    #expect(photoStore.gifticonsCallCount == 1)
  }
}
