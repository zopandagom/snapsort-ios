import Core
import Foundation
import MapInterface
import MapTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
@testable import LibraryFeature

/// 여행 폴더 목록·상세 테스트의 공통 준비. 기기는 Asia/Seoul·ko_KR 이다.
@MainActor
enum TripFixture {
  static let locale = Locale(identifier: "ko_KR")
  /// 제주 여행 중심점. 반올림 키는 (3350, 12653).
  static let jejuCenter = Coordinate(latitude: 33.4996, longitude: 126.5312)
  static let jejuKey = RoundedCoordinate(latitudeHundredths: 3350, longitudeHundredths: 12653)!
  /// 도쿄 여행 중심점. 반올림 키는 (3568, 13976).
  static let tokyoCenter = Coordinate(latitude: 35.6812, longitude: 139.7614)
  static let tokyoKey = RoundedCoordinate(latitudeHundredths: 3568, longitudeHundredths: 13976)!
  /// 뉴욕 여행 중심점. 경도 추정 UTC-5 가 서울 기기와 달라 대체 규칙은 고정 오프셋을 쓴다.
  static let newYorkCenter = Coordinate(latitude: 40.7128, longitude: -74.006)
  static let newYorkKey = RoundedCoordinate(latitudeHundredths: 4071, longitudeHundredths: -7401)!

  /// 2026-07-10 09:00 ~ 07-12 18:00(서울) 제주 여행. 사진 `jeju-0`…`jeju-3`.
  static let jeju = Trip(
    assetIDs: (0 ..< 4).map { "jeju-\($0)" },
    startDate: .seoul(2026, 7, 10, hour: 9),
    endDate: .seoul(2026, 7, 12, hour: 18),
    center: TripFixture.jejuCenter
  )

  /// 2026-08-01 10:00 ~ 08-03 20:00(서울) 도쿄 여행. 사진 `tokyo-0`…`tokyo-2`.
  static let tokyo = Trip(
    assetIDs: (0 ..< 3).map { "tokyo-\($0)" },
    startDate: .seoul(2026, 8, 1, hour: 10),
    endDate: .seoul(2026, 8, 3, hour: 20),
    center: TripFixture.tokyoCenter
  )

  /// 뉴욕 여름 여행. 첫 사진 2026-07-10 10:00 EDT, 마지막 사진 07-15 00:30 EDT.
  /// 실제 시간대로는 07-10~07-15 이고, 시간대를 모르면(대체 규칙, UTC-5 고정) 마지막 날이 07-14 로 밀린다(알려진 한계 (a)).
  static let newYork = Trip(
    assetIDs: (0 ..< 3).map { "ny-\($0)" },
    startDate: .newYork(2026, 7, 10, hour: 10),
    endDate: .newYork(2026, 7, 15, hour: 0, minute: 30),
    center: TripFixture.newYorkCenter
  )

  /// 제주 여행에 캐시된 이름·시간대. 상세 테스트에서 이름 요청이 끼지 않게 둔다.
  static let jejuPlace = [
    TripFixture.jejuKey: CachedPlace(name: .named("제주특별자치도 제주시"), timeZoneIdentifier: "Asia/Seoul"),
  ]

  /// 판정이 바뀌어 제주 여행에 더해지는 마지막 사진.
  static let extraJejuPhoto = IndexedImage(
    asset: .stub(id: "jeju-4", creationDate: .seoul(2026, 7, 12, hour: 19), coordinate: TripFixture.jejuCenter),
    labels: [],
    textRecognition: .notNeeded,
    categories: [.landscape]
  )

  /// 제주 여행에 마지막 사진 `jeju-4` 가 더해진 판정. 중심점은 같다.
  static let jejuWithExtraPhoto = Trip(
    assetIDs: TripFixture.jeju.assetIDs + ["jeju-4"],
    startDate: TripFixture.jeju.startDate,
    endDate: .seoul(2026, 7, 12, hour: 19),
    center: TripFixture.jejuCenter
  )

  static let tokyoInfo = PlaceInfo(name: "일본 도쿄 지요다구", timeZoneIdentifier: "Asia/Tokyo")

  /// 도쿄 여행과 그 사진만 있는 저장소. 장소 캐시를 정할 수 있다.
  static func tokyoStore(
    places: [RoundedCoordinate: CachedPlace] = [:],
    placesLocaleIdentifier: String = "ko_KR"
  ) -> PhotoStoreClientFake {
    PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.tokyo],
      places: places,
      placesLocaleIdentifier: placesLocaleIdentifier
    )
  }

  /// 여행 사진을 첫 사진 시각부터 마지막 사진 시각까지 고르게 찍은 풍경 사진으로 만든다.
  static func photos(of trip: Trip) -> [IndexedImage] {
    let count = trip.assetIDs.count
    let span = trip.endDate.timeIntervalSince(trip.startDate)
    return trip.assetIDs.enumerated().map { index, id in
      let offset = count > 1 ? span * Double(index) / Double(count - 1) : 0
      return IndexedImage(
        asset: .stub(id: id, creationDate: trip.startDate.addingTimeInterval(offset), coordinate: trip.center),
        labels: [],
        textRecognition: .notNeeded,
        categories: [.landscape]
      )
    }
  }

  /// 그 시각에 만든 캡처.
  static func capture(_ id: String, _ category: ImageCategory, at date: Date) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: date, isScreenshot: true),
      labels: [],
      textRecognition: .recognized([]),
      categories: [category]
    )
  }

  static func listModel(
    photoStore: PhotoStoreClientFake?,
    photoLibrary: PhotoLibraryClientFake = PhotoLibraryClientFake(currentState: .authorized),
    clock: TestClock = TestClock(now: .seoul(2026, 10, 21, hour: 9), calendar: .seoul),
    locale: Locale = TripFixture.locale
  ) -> TripListModel {
    TripListModel(photoLibrary: photoLibrary, photoStore: photoStore, calendar: { clock.calendar }, locale: { locale })
  }

  /// - Parameter placeNameTimeout: 기본은 테스트가 시한에 닿지 않을 만큼 길다.
  static func detailModel(
    photoStore: PhotoStoreClientFake?,
    map: MapClientFake = MapClientFake(),
    clock: TestClock = TestClock(now: .seoul(2026, 10, 21, hour: 9), calendar: .seoul),
    locale: Locale = TripFixture.locale,
    placeNameTimeout: Duration = .seconds(3600)
  ) -> TripDetailModel {
    TripDetailModel(
      photoStore: photoStore,
      map: map,
      calendar: { clock.calendar },
      locale: { locale },
      placeNameTimeout: placeNameTimeout
    )
  }
}

/// 상세 화면 하나를 연 것처럼 `onAppear(trip:visit:)` 를 돌린다. 같은 `visit` 으로 다시 열면 사진 상세에서 돌아온 것이다.
@MainActor
func openDetail(_ model: TripDetailModel, trip: Trip, visit: UUID) -> Task<Void, Never> {
  Task { await model.onAppear(trip: trip, visit: visit) }
}

extension TripListContent {
  var items: [TripFolderItem]? {
    guard case let .loaded(items) = self else { return nil }
    return items
  }

  /// 줄마다 첫 사진 식별자. 읽기 전이나 실패면 nil.
  var ids: [ImageAsset.ID]? {
    self.items?.map(\.id)
  }
}

extension TripDetailContent {
  var detail: TripDetail? {
    guard case let .loaded(detail) = self else { return nil }
    return detail
  }
}

extension Calendar {
  static let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }()
}

extension Date {
  static func newYork(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
    Calendar.newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }
}

/// 테스트가 바꾸는 기기 로캘. Model 의 `locale` 클로저가 읽는다.
final class LocaleBox: Sendable {
  private let state: Mutex<Locale>

  init(_ locale: Locale) {
    self.state = Mutex(locale)
  }

  var value: Locale {
    get { self.state.withLock { $0 } }
    set { self.state.withLock { $0 = newValue } }
  }
}
