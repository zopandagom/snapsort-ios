import Foundation
import Synchronization
import Testing
import TripPlaceInterface
import TripPlaceTesting

struct TripPlaceClientFakeTests {
  @Test("회차를 부른 로캘을 순서대로 기록한다")
  func recordsLocales() async {
    let fake = TripPlaceClientFake()

    await fake.prefetchPlaces(locale: Locale(identifier: "ko_KR"))
    await fake.prefetchPlaces(locale: Locale(identifier: "en_US"))

    #expect(fake.prefetchLocaleIdentifiers == ["ko_KR", "en_US"])
    #expect(fake.cancelledPrefetchCount == 0)
  }

  @Test("onPrefetch 를 기다리는 동안 취소되면 취소된 호출로 센다")
  func countsCancelledPrefetch() async {
    let fake = TripPlaceClientFake { _ in
      try? await Task.sleep(for: .seconds(3600))
    }

    let round = Task { await fake.prefetchPlaces(locale: Locale(identifier: "ko_KR")) }
    while fake.prefetchLocaleIdentifiers.isEmpty {
      await Task.yield()
    }
    round.cancel()
    await round.value

    #expect(fake.cancelledPrefetchCount == 1)
  }

  @Test("변경 신호를 구독자 모두에게 보내고, 구독을 끝내면 목록에서 빠진다")
  func sendsChangesToSubscribers() async {
    let fake = TripPlaceClientFake()
    let first = await fake.placeChanges()
    let second = await fake.placeChanges()
    #expect(fake.activeSubscriberCount == 2)

    fake.sendPlaceChange()
    var firstIterator = first.makeAsyncIterator()
    var secondIterator = second.makeAsyncIterator()
    #expect(await firstIterator.next() != nil)
    #expect(await secondIterator.next() != nil)

    let consumer = Task {
      for await _ in await fake.placeChanges() {}
    }
    while fake.activeSubscriberCount < 3 {
      await Task.yield()
    }
    consumer.cancel()
    await consumer.value
    #expect(fake.activeSubscriberCount == 2)
  }

  @Test("회차 시작·취소·끝과 저장소 출입 막기·열기를 순서대로 기록하고 onEvent 로도 넘긴다")
  func recordsEvents() async {
    let forwarded = Mutex<[TripPlaceClientFake.Event]>([])
    let fake = TripPlaceClientFake(
      onPrefetch: { _ in try? await Task.sleep(for: .seconds(3600)) },
      onEvent: { event in forwarded.withLock { $0.append(event) } }
    )

    let round = Task { await fake.prefetchPlaces(locale: Locale(identifier: "ko_KR")) }
    while fake.prefetchLocaleIdentifiers.isEmpty {
      await Task.yield()
    }
    round.cancel()
    await round.value
    await fake.holdStoreAccess()
    await fake.allowStoreAccess()

    #expect(fake.events == [
      .prefetchStarted,
      .prefetchCancelled,
      .prefetchReturned,
      .holdStoreAccess,
      .allowStoreAccess,
    ])
    #expect(forwarded.withLock { $0 } == fake.events)
  }

  @Test("진행 알림은 도는 회차에만 가고, 회차가 없거나 돌아온 뒤에는 버린다")
  func sendsPrefetchProgressOnlyToRunningRound() async {
    let release = Mutex(false)
    let fake = TripPlaceClientFake { _ in
      while !release.withLock({ $0 }), !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(1))
      }
    }
    let received = Mutex<[TripPlacePrefetchProgress]>([])

    fake.sendPrefetchProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 9))
    let round = Task {
      await fake.prefetchPlaces(locale: Locale(identifier: "ko_KR")) { value in
        received.withLock { $0.append(value) }
      }
    }
    while fake.prefetchLocaleIdentifiers.isEmpty {
      await Task.yield()
    }
    fake.sendPrefetchProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 2))
    fake.sendPrefetchProgress(TripPlacePrefetchProgress(doneCount: 1, totalCount: 2))
    release.withLock { $0 = true }
    await round.value
    fake.sendPrefetchProgress(TripPlacePrefetchProgress(doneCount: 2, totalCount: 2))

    #expect(received.withLock { $0 } == [
      TripPlacePrefetchProgress(doneCount: 0, totalCount: 2),
      TripPlacePrefetchProgress(doneCount: 1, totalCount: 2),
    ])
  }
}
