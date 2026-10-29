import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 이름을 묻는 동안 기기 로캘이 바뀔 때의 장소 이름. 키가 같아도 이름의 주인(키·로캘)이 바뀌었으면 옛 로캘 응답으로 덮지 않는다.
@MainActor
struct TripDetailPlaceNameLocaleTests {
  @Test("묻는 동안 로캘이 바뀌면 옛 로캘 응답은 이름을 바꾸지 않고 새 로캘 응답만 반영한다")
  func localeChangeIgnoresPreviousLocaleResponse() async {
    // 0 ko_KR, 1 en_US. 둘 다 붙잡는다.
    let gates = CallGates(holding: [0, 1], ignoresCancellation: true)
    defer {
      gates.open(0)
      gates.open(1)
    }
    let map = MapClientFake(
      placeNameResults: [TripFixture.jejuKey: .success(PlaceInfo(name: "제주", timeZoneIdentifier: "Asia/Seoul"))],
      onPlaceName: { await gates.pass($0) }
    )
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju]
    )
    let locale = LocaleBox(Locale(identifier: "ko_KR"))
    let model = TripDetailModel(
      photoStore: photoStore,
      map: map,
      calendar: { .seoul },
      locale: { locale.value },
      placeNameTimeout: .seconds(3600)
    )
    let appear = openDetail(model, trip: TripFixture.jeju, visit: UUID())
    await waitUntil { gates.hasEntered(0) }
    #expect(model.placeNameRequest?.localeIdentifier == "ko_KR")

    locale.value = Locale(identifier: "en_US")
    model.dayChanged()
    await waitUntil { gates.hasEntered(1) }
    #expect(model.placeNameRequest?.localeIdentifier == "en_US")

    // 옛 로캘 응답은 캐시에 쓰지만 지금 이름의 주인이 아니라 이름을 바꾸지 않는다.
    gates.open(0)
    await waitUntil { photoStore.savedPlaces.count == 1 }
    await settle()
    #expect(model.placeName == .loading)
    #expect(model.placeNameRequest?.localeIdentifier == "en_US")

    gates.open(1)
    await waitUntil { model.placeName == .named("제주") }
    #expect(model.placeNameRequest?.localeIdentifier == "en_US")
    #expect(photoStore.savedPlaces.map(\.localeIdentifier) == ["ko_KR", "en_US"])
    await cancelAndWait(appear)
  }
}
