import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 검색 Model 의 장소 이름 대조. 장소 이름은 저장소에 캐시된 것만 쓰고 새로 찾지 않는다.
@MainActor
struct SearchModelPlaceTests {
  @Test("지금 로캘로 캐시된 이름이 맞은 여행만 여행 줄로 보이고, 기간은 캐시된 시간대로 계산한다")
  func cachedNamedPlaceMatchesTrip() async {
    let photoStore = TripFixture.tokyoStore(places: [
      TripFixture.tokyoKey: CachedPlace(name: .named("일본 도쿄 지요다구"), timeZoneIdentifier: "Asia/Tokyo"),
    ])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("도쿄")
    await waitUntil { model.results != nil }
    #expect(model.results?.trips.map(\.placeName) == ["일본 도쿄 지요다구"])
    #expect(model.results?.trips.first?.trip == TripFixture.tokyo)
    #expect(model.results?.trips.first?.period.timeZone.identifier == "Asia/Tokyo")
    #expect(model.results?.trips.first?.period.isTimeZoneKnown == true)

    await cancelAndWait(appear)
  }

  @Test("시간대를 모르는 캐시는 대체 규칙으로 기간을 계산한다")
  func unknownTimeZoneUsesFallbackPeriod() async {
    let photoStore = TripFixture.tokyoStore(places: [
      TripFixture.tokyoKey: CachedPlace(name: .named("일본 도쿄 지요다구"), timeZoneIdentifier: nil),
    ])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("도쿄")
    await waitUntil { model.results != nil }
    #expect(model.results?.trips.count == 1)
    #expect(model.results?.trips.first?.period.isTimeZoneKnown == false)

    await cancelAndWait(appear)
  }

  @Test("다른 로캘로 캐시된 이름, 이름을 못 찾은 캐시, 캐시 없음은 맞지 않고 저장소의 장소 캐시도 바뀌지 않는다")
  func onlyCurrentLocaleNamedPlacesMatch() async throws {
    let otherLocale = TripFixture.tokyoStore(
      places: [TripFixture.tokyoKey: CachedPlace(
        name: .named("Chiyoda City, Tokyo"),
        timeZoneIdentifier: "Asia/Tokyo"
      )],
      placesLocaleIdentifier: "en_US"
    )
    let unnamed = TripFixture.tokyoStore(
      places: [TripFixture.tokyoKey: CachedPlace(name: .unnamed, timeZoneIdentifier: "Asia/Tokyo")]
    )
    let noCache = TripFixture.tokyoStore()

    for photoStore in [otherLocale, unnamed, noCache] {
      let before = try await photoStore.places(for: [TripFixture.tokyoKey], localeIdentifier: "ko_KR")
      let (model, _) = SearchFixture.model(photoStore: photoStore)
      let appear = Task { await model.onAppear() }
      await waitUntil { model.loadState == .loaded }

      // 이름이 있었다면 맞았을 낱말들이다.
      for word in ["도쿄", "Tokyo", "Chiyoda"] {
        model.queryChanged(word)
        await waitUntil { model.results?.query == word }
        #expect(model.results?.trips.isEmpty == true)
      }
      let after = try await photoStore.places(for: [TripFixture.tokyoKey], localeIdentifier: "ko_KR")
      #expect(after == before)
      await cancelAndWait(appear)
    }
  }

  @Test("사진 식별자가 없는 여행은 이름이 캐시돼 있어도 여행 줄에서 빠진다")
  func tripWithoutAssetsIsOmitted() async {
    let emptyTrip = Trip(
      assetIDs: [],
      startDate: .seoul(2026, 7, 1, hour: 9),
      endDate: .seoul(2026, 7, 2, hour: 9),
      center: TripFixture.jejuCenter
    )
    let photoStore = PhotoStoreClientFake(trips: [emptyTrip], places: TripFixture.jejuPlace)
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("제주")
    await waitUntil { model.results != nil }
    #expect(model.results?.trips.isEmpty == true)

    await cancelAndWait(appear)
  }
}
