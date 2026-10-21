import Core
import Foundation
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 여행 폴더 목록 읽기·다시 읽기. 읽기를 붙잡을 때는 `onTrips` 에 `CallGates` 를, 실패는 `tripsErrors` 를 쓴다.
@MainActor
struct TripListModelTests {
  @Test("최신 여행이 위이고, 줄마다 사진 수·가운데 대표 사진·지금 로캘로 캐시된 이름을 담는다")
  func showsTripsNewestFirst() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju, TripFixture.tokyo],
      places: [TripFixture.jejuKey: CachedPlace(name: .named("제주특별자치도 제주시"), timeZoneIdentifier: "Asia/Seoul")]
    )
    let model = TripFixture.listModel(photoStore: photoStore)

    let appear = Task { await model.onAppear() }
    await waitUntil { model.content != .loading }

    let items = model.content.items
    #expect(items?.map(\.id) == ["tokyo-0", "jeju-0"])
    #expect(items?.map(\.photoCount) == [3, 4])
    #expect(items?.map(\.cover?.id) == ["tokyo-1", "jeju-2"])
    #expect(items?.map(\.placeName) == [nil, "제주특별자치도 제주시"])

    await cancelAndWait(appear)
  }

  @Test("다른 로캘로 캐시된 이름과 이름을 못 찾은 캐시는 보이지 않는다")
  func showsOnlyCurrentLocaleNames() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: [TripFixture.jejuKey: CachedPlace(name: .named("Jeju-si"), timeZoneIdentifier: "Asia/Seoul")],
      placesLocaleIdentifier: "en_US"
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content != .loading }
    #expect(model.content.items?.first?.placeName == nil)
    await cancelAndWait(appear)

    let unnamedStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: [TripFixture.jejuKey: CachedPlace(name: .unnamed, timeZoneIdentifier: nil)]
    )
    let unnamedModel = TripFixture.listModel(photoStore: unnamedStore)
    let unnamedAppear = Task { await unnamedModel.onAppear() }
    await waitUntil { unnamedModel.content != .loading }
    #expect(unnamedModel.content.items?.first?.placeName == nil)
    await cancelAndWait(unnamedAppear)
  }

  @Test("가운데 사진이 저장소에 없으면 첫 사진, 그것도 없으면 마지막 사진, 모두 없으면 대표가 없다")
  func coverFallsBack() async {
    let trip = Trip(
      assetIDs: ["a", "b", "c"],
      startDate: .seoul(2026, 7, 1, hour: 9),
      endDate: .seoul(2026, 7, 2, hour: 9),
      center: TripFixture.jejuCenter
    )
    let photos = TripFixture.photos(of: trip)
    for (stored, expected) in [(["a", "c"], "a"), (["c"], "c"), ([], nil)] as [([String], String?)] {
      let photoStore = PhotoStoreClientFake(images: photos.filter { stored.contains($0.id) }, trips: [trip])
      let model = TripFixture.listModel(photoStore: photoStore)
      let appear = Task { await model.onAppear() }
      await waitUntil { model.content != .loading }
      #expect(model.content.items?.first?.cover?.id == expected)
      await cancelAndWait(appear)
    }
  }

  @Test("캐시된 여행지 시간대가 있으면 기간을 그 시간대로 계산하고, 없으면 대체 규칙으로 계산한다")
  func periodUsesCachedTimeZone() async {
    let known = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.newYork),
      trips: [TripFixture.newYork],
      places: [TripFixture.newYorkKey: CachedPlace(name: nil, timeZoneIdentifier: "America/New_York")]
    )
    let knownModel = TripFixture.listModel(photoStore: known)
    let knownAppear = Task { await knownModel.onAppear() }
    await waitUntil { knownModel.content != .loading }
    let knownPeriod = knownModel.content.items?.first?.period
    #expect(knownPeriod?.isTimeZoneKnown == true)
    #expect(knownPeriod?.firstDay == .date(2026, 7, 10))
    #expect(knownPeriod?.lastDay == .date(2026, 7, 15))
    await cancelAndWait(knownAppear)

    let unknown = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.newYork),
      trips: [TripFixture.newYork]
    )
    let unknownModel = TripFixture.listModel(photoStore: unknown)
    let unknownAppear = Task { await unknownModel.onAppear() }
    await waitUntil { unknownModel.content != .loading }
    let unknownPeriod = unknownModel.content.items?.first?.period
    #expect(unknownPeriod?.isTimeZoneKnown == false)
    // 알려진 한계 (a): 시간대를 모르면 마지막 날이 하루 이르다. 상세를 온라인으로 열면 캐시돼 고쳐진다.
    #expect(unknownPeriod?.lastDay == .date(2026, 7, 14))
    await cancelAndWait(unknownAppear)
  }

  @Test("사진 식별자가 없는 여행은 빠지고, 여행이 없으면 빈 목록이다")
  func dropsTripsWithoutPhotos() async {
    let empty = Trip(
      assetIDs: [],
      startDate: .seoul(2026, 9, 1, hour: 9),
      endDate: .seoul(2026, 9, 2, hour: 9),
      center: TripFixture.jejuCenter
    )
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [empty, TripFixture.jeju]
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content != .loading }
    #expect(model.content.ids == ["jeju-0"])
    await cancelAndWait(appear)

    let noTrips = TripFixture.listModel(photoStore: PhotoStoreClientFake())
    let noTripsAppear = Task { await noTrips.onAppear() }
    await waitUntil { noTrips.content != .loading }
    #expect(noTrips.content == .loaded([]))
    await cancelAndWait(noTripsAppear)
  }

  @Test("장소 캐시는 여행이 여럿이어도 읽기마다 한 번만 읽고, 목록은 장소 이름을 묻지 않는다")
  func readsPlacesOnce() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju, TripFixture.tokyo]
    )
    let model = TripFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.content != .loading }
    #expect(photoStore.placesCallCount == 1)
    #expect(photoStore.savedPlaces.isEmpty)
    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 실패다")
  func missingStoreShowsFailed() async {
    let model = TripFixture.listModel(photoStore: nil)
    await model.onAppear()
    #expect(model.content == .failed)
  }
}
