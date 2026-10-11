import Core
import Foundation
import Testing

struct TravelDetectorTests {
  @Test("자주 가는 지역에서만 찍었으면 여행이 없다")
  func noTripAtFrequentRegion() {
    #expect(TravelDetector.trips(in: home, calendar: calendar).isEmpty)
  }

  @Test("자주 가는 지역 밖에서 며칠 찍은 사진을 여행 하나로 묶는다")
  func detectsTrip() throws {
    let busanPhotos = photos("busan", at: busan, days: 2 ... 4, perDay: 3, month: 5)

    let trips = TravelDetector.trips(in: home + busanPhotos, calendar: calendar)

    let trip = try #require(trips.only)
    #expect(trip.assetIDs == busanPhotos.map(\.id))
    #expect(trip.startDate == date(month: 5, day: 2, hour: 10))
    #expect(trip.endDate == date(month: 5, day: 4, hour: 10).addingTimeInterval(2 * 60))
    #expect(abs(trip.center.latitude - busan.latitude) < 0.001)
    #expect(abs(trip.center.longitude - busan.longitude) < 0.001)
  }

  @Test("여행지가 여러 곳이면 중심점은 사진이 가장 많은 곳에 둔다")
  func centerIsInMainDestination() throws {
    let busanPhotos = photos("busan", at: busan, days: 2 ... 2, perDay: 6, month: 5)
    let jejuPhotos = photos("jeju", at: jeju, days: 3 ... 3, perDay: 5, month: 5)

    let trip = try #require(TravelDetector.trips(in: home + busanPhotos + jejuPhotos, calendar: calendar).only)

    #expect(trip.assetIDs == (busanPhotos + jejuPhotos).map(\.id))
    #expect(abs(trip.center.latitude - busan.latitude) < 0.001)
    #expect(abs(trip.center.longitude - busan.longitude) < 0.001)
  }

  @Test("여행지 두 곳의 사진 수가 같으면 칸 순서가 앞선(남쪽) 곳에 중심점을 둔다")
  func centerTieBreaksBySouthernRegion() throws {
    let busanPhotos = photos("busan", at: busan, days: 2 ... 2, perDay: 5, month: 5)
    let jejuPhotos = photos("jeju", at: jeju, days: 3 ... 3, perDay: 5, month: 5)

    let trip = try #require(TravelDetector.trips(in: home + busanPhotos + jejuPhotos, calendar: calendar).only)

    #expect(abs(trip.center.latitude - jeju.latitude) < 0.001)
    #expect(abs(trip.center.longitude - jeju.longitude) < 0.001)
  }

  @Test("집 양쪽의 여행지를 이어 다녀도 중심점이 집 근처에 떨어지지 않는다")
  func centerIsNotNearHome() throws {
    // 사진 수로 가중한 전체 평균(37.65, 127.17)은 서울 칸의 이웃 칸에 떨어진다.
    let incheon = Coordinate(latitude: 37.4563, longitude: 126.7052)
    let chuncheon = Coordinate(latitude: 37.8813, longitude: 127.7298)
    let incheonPhotos = photos("incheon", at: incheon, days: 2 ... 2, perDay: 6, month: 5)
    let chuncheonPhotos = photos("chuncheon", at: chuncheon, days: 3 ... 3, perDay: 5, month: 5)

    let trip = try #require(
      TravelDetector.trips(in: home + incheonPhotos + chuncheonPhotos, calendar: calendar).only
    )

    // 서울 칸과 맞닿은 칸(자주 가는 지역) 밖이어야 한다.
    func cell(_ degrees: Double) -> Int {
      Int((degrees / 0.18).rounded(.down))
    }
    let rowGap = abs(cell(trip.center.latitude) - cell(seoul.latitude))
    let columnGap = abs(cell(trip.center.longitude) - cell(seoul.longitude))
    #expect(max(rowGap, columnGap) > 1)
  }

  @Test("여행에서 집보다 사진을 훨씬 많이 찍어도 집 근처를 여행으로 보지 않는다")
  func manyTripPhotosDoNotMoveFrequentRegion() throws {
    let jejuPhotos = photos("jeju", at: jeju, days: 1 ... 4, perDay: 100, month: 5)

    let trips = TravelDetector.trips(in: home + jejuPhotos, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == jejuPhotos.map(\.id))
  }

  @Test("한 달 넘게 머물러도 60일 미만이면 여행이다")
  func longStayIsTrip() throws {
    let stay = (1 ... 30).map { photo("stay-5-\($0)", at: jeju, month: 5, day: $0) }
      + (1 ... 10).map { photo("stay-6-\($0)", at: jeju, month: 6, day: $0) }

    let trips = TravelDetector.trips(in: home + stay, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == stay.map(\.id))
  }

  @Test("달 경계에 걸쳐 세 달에 나와도 두 달이 안 되는 체류는 여행으로 본다")
  func monthBoundaryStayIsTrip() throws {
    let stay = [photo("stay-5-31", at: jeju, month: 5, day: 31)]
      + (1 ... 30).map { photo("stay-6-\($0)", at: jeju, month: 6, day: $0) }
      + [photo("stay-7-1", at: jeju, month: 7, day: 1)]

    let trips = TravelDetector.trips(in: home + stay, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == stay.map(\.id))
  }

  @Test("같은 여행지를 몇 달 간격으로 여러 번 가도 각각 여행이다")
  func repeatedTripsToSamePlaceAreTrips() {
    let visits = [1, 5, 9].map { month in photos("jeju-\(month)", at: jeju, days: 29 ... 30, perDay: 5, month: month) }

    let trips = TravelDetector.trips(in: home + visits.flatMap(\.self), calendar: calendar)

    #expect(trips.map(\.assetIDs) == visits.map { $0.map(\.id) })
  }

  @Test("앞뒤 3개월 안에 같은 곳을 한 번 더 갔어도 달 경계에 걸친 여행은 여행이다")
  func tripAcrossMonthBoundaryWithOneMoreVisit() throws {
    let earlier = [photo("jeju-earlier", at: jeju, month: 5, day: 15)]
    let trip = photos("jeju-7", at: jeju, days: 30 ... 31, perDay: 5, month: 7)
      + photos("jeju-8", at: jeju, days: 1 ... 2, perDay: 5, month: 8)

    let trips = TravelDetector.trips(in: home + earlier + trip, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == trip.map(\.id))
  }

  /// 앞뒤 3개월 안에 방문이 세 번이면 자주 가는 곳으로 본다. 가운데 방문만 그 조건을 채운다.
  @Test("3개월 간격으로 세 번 간 곳은 가운데 방문을 자주 가는 곳으로 본다")
  func quarterlyVisitsMakeMiddleVisitFrequent() {
    let visits = [5, 8, 11].map { month in photos("jeju-\(month)", at: jeju, days: 29 ... 30, perDay: 5, month: month) }

    let trips = TravelDetector.trips(in: home + visits.flatMap(\.self), calendar: calendar)

    #expect(trips.map(\.assetIDs) == [visits[0].map(\.id), visits[2].map(\.id)])
  }

  @Test("방문 첫날과 마지막 날이 60일 미만이면 여행이고, 60일 이상이면 생활한 곳으로 본다", arguments: [(59, true), (60, false)])
  func longStayBoundary(stayDays: Int, isTrip: Bool) {
    let start = date(month: 5, day: 1, hour: 12)
    let stay = (0 ... stayDays).map { offset in
      ImageAsset(
        id: "stay-\(offset)",
        creationDate: calendar.date(byAdding: .day, value: offset, to: start),
        coordinate: jeju,
        pixelWidth: 4032,
        pixelHeight: 3024,
        isScreenshot: false
      )
    }

    let trips = TravelDetector.trips(in: home + stay, calendar: calendar)

    #expect(trips.map(\.assetIDs) == (isTrip ? [stay.map(\.id)] : []))
  }

  @Test("앞뒤 3개월을 넘게 떨어진 방문은 세지 않는다")
  func visitsBeyondWindowAreNotCounted() {
    let visits = photos("jeju-5", at: jeju, days: 29 ... 30, perDay: 5, month: 5)
      + photos("jeju-8", at: jeju, days: 29 ... 30, perDay: 5, month: 8)
      + photos("jeju-12", at: jeju, days: 1 ... 2, perDay: 5, month: 12)

    #expect(TravelDetector.trips(in: home + visits, calendar: calendar).count == 3)
  }

  @Test("여행 중에 맞닿은 칸을 오가도 방문 한 번으로 센다")
  func hoppingBetweenNeighborRegionsIsOneVisit() throws {
    // 제주 칸과 동쪽으로 맞닿은 칸.
    let jejuEast = Coordinate(latitude: 33.4996, longitude: 126.6)
    let trip = photos("a1", at: jeju, days: 1 ... 1, perDay: 5, month: 5)
      + photos("b2", at: jejuEast, days: 2 ... 3, perDay: 5, month: 5)
      + photos("a4", at: jeju, days: 4 ... 4, perDay: 5, month: 5)
      + photos("b5", at: jejuEast, days: 5 ... 6, perDay: 5, month: 5)
      + photos("a7", at: jeju, days: 7 ... 7, perDay: 5, month: 5)

    let trips = TravelDetector.trips(in: home + trip, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == trip.map(\.id))
  }

  @Test("방문 수로 자주 가는 곳이 된 본가와 맞닿은 칸은 여행이 아니다")
  func neighborOfRegularlyVisitedRegionIsNotTrip() {
    // 부산 칸과 동쪽으로 맞닿은 칸.
    let busanEast = Coordinate(latitude: 35.1796, longitude: 129.25)
    let parents = photos("parents-1", at: busan, days: 5 ... 6, perDay: 5, month: 1)
      + photos("parents-2", at: busan, days: 15 ... 16, perDay: 5, month: 2)
      + photos("parents-3", at: busan, days: 25 ... 26, perDay: 5, month: 3)
    let nearby = photos("nearby", at: busanEast, days: 20 ... 21, perDay: 5, month: 2)

    #expect(TravelDetector.trips(in: home + parents + nearby, calendar: calendar).isEmpty)
  }

  @Test("보관함이 짧아도 찍은 날이 가장 많은 지역은 여행으로 보지 않는다")
  func shortLibraryKeepsMostVisitedRegion() throws {
    let shortHome = (1 ... 10).map { photo("home-\($0)", at: seoul, month: 5, day: $0) }
    let busanPhotos = photos("busan", at: busan, days: 20 ... 21, perDay: 5, month: 5)

    let trips = TravelDetector.trips(in: shortHome + busanPhotos, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == busanPhotos.map(\.id))
  }

  @Test("찍은 날 수가 같은 두 지역뿐이면 칸 순서가 앞선(남쪽) 곳을 자주 가는 지역으로 본다")
  func mostVisitedTieBreaksBySouthernRegion() throws {
    let seoulPhotos = (1 ... 10).map { photo("seoul-\($0)", at: seoul, month: 5, day: $0) }
    let busanPhotos = (11 ... 20).map { photo("busan-\($0)", at: busan, month: 5, day: $0) }

    let trips = TravelDetector.trips(in: seoulPhotos + busanPhotos, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == seoulPhotos.map(\.id))
  }

  @Test("이사한 뒤의 일상 사진은 여행이 아니다")
  func movingIsNotTrip() {
    let before = (1 ... 4).flatMap { month in (1 ... 20).map { photo(
      "seoul-\(month)-\($0)",
      at: seoul,
      month: month,
      day: $0
    ) } }
    let after = (5 ... 8).flatMap { month in
      (1 ... 20).map { photo("daejeon-\(month)-\($0)", at: daejeon, month: month, day: $0) }
    }

    #expect(TravelDetector.trips(in: before + after, calendar: calendar).isEmpty)
  }

  @Test("앞뒤 3개월 안에 세 번 간 본가는 여행이 아니다")
  func regularlyVisitedRegionIsNotTrip() {
    let parents = photos("parents-1", at: busan, days: 5 ... 6, perDay: 5, month: 1)
      + photos("parents-2", at: busan, days: 15 ... 16, perDay: 5, month: 2)
      + photos("parents-3", at: busan, days: 25 ... 26, perDay: 5, month: 3)

    #expect(TravelDetector.trips(in: home + parents, calendar: calendar).isEmpty)
  }

  @Test("자주 가는 지역과 맞닿은 칸은 여행이 아니다")
  func neighborRegionIsNotTrip() {
    // 서울 시청에서 북쪽으로 약 7km. 위도 칸 경계(37.62)를 넘는다.
    let nearby = photos(
      "nearby",
      at: Coordinate(latitude: 37.63, longitude: 126.978),
      days: 2 ... 3,
      perDay: 5,
      month: 5
    )

    #expect(TravelDetector.trips(in: home + nearby, calendar: calendar).isEmpty)
  }

  @Test("여행지 사진이 없는 날이 하루면 같은 여행으로 잇고, 이틀이면 나눈다")
  func joinsAcrossOneEmptyDay() {
    let joined = photos("first", at: busan, days: 1 ... 1, perDay: 5, month: 5)
      + photos("second", at: busan, days: 3 ... 3, perDay: 5, month: 5)
    let split = photos("first", at: busan, days: 1 ... 1, perDay: 5, month: 5)
      + photos("second", at: busan, days: 4 ... 4, perDay: 5, month: 5)

    #expect(TravelDetector.trips(in: home + joined, calendar: calendar).map(\.assetIDs) == [joined.map(\.id)])
    #expect(
      TravelDetector.trips(in: home + split, calendar: calendar).map(\.assetIDs)
        == [Array(split.prefix(5)).map(\.id), Array(split.suffix(5)).map(\.id)]
    )
  }

  @Test("중간에 자주 가는 지역에서 찍은 날이 있으면 여행을 나눈다")
  func returningHomeSplitsTrip() {
    let busanPhotos = photos("busan", at: busan, days: 1 ... 1, perDay: 5, month: 5)
    let homeDay = [photo("home-day", at: seoul, month: 5, day: 2)]
    let jejuPhotos = photos("jeju", at: jeju, days: 3 ... 3, perDay: 5, month: 5)

    let trips = TravelDetector.trips(in: home + busanPhotos + homeDay + jejuPhotos, calendar: calendar)

    #expect(trips.map(\.assetIDs) == [busanPhotos.map(\.id), jejuPhotos.map(\.id)])
  }

  @Test("여행지 사진을 찍은 날 자주 가는 지역으로 돌아왔으면 다음 여행지 사진과 잇지 않는다")
  func returningHomeOnSameDaySplitsTrip() {
    let busanPhotos = photos("busan", at: busan, days: 1 ... 1, perDay: 5, month: 5)
    let homeEvening = [photo("home-evening", at: seoul, month: 5, day: 1, hour: 21)]
    let jejuPhotos = photos("jeju", at: jeju, days: 3 ... 3, perDay: 5, month: 5)

    let trips = TravelDetector.trips(in: home + busanPhotos + homeEvening + jejuPhotos, calendar: calendar)

    #expect(trips.map(\.assetIDs) == [busanPhotos.map(\.id), jejuPhotos.map(\.id)])
  }

  @Test("최소 사진 수(5장)보다 적게 찍은 곳은 여행이 아니고, 5장이면 당일치기도 여행이다")
  func minimumPhotoCount() {
    let passingBy = photos("busan", at: busan, days: 2 ... 3, perDay: 2, month: 5)
    let dayTrip = photos("busan", at: busan, days: 2 ... 2, perDay: 5, month: 5)

    #expect(TravelDetector.trips(in: home + passingBy, calendar: calendar).isEmpty)
    #expect(TravelDetector.trips(in: home + dayTrip, calendar: calendar).map(\.assetIDs) == [dayTrip.map(\.id)])
  }

  @Test(
    "위도·경도가 유효하지 않은 이미지는 판정에 쓰지 않는다",
    arguments: [
      Coordinate(latitude: .nan, longitude: 126.978),
      Coordinate(latitude: 37.5665, longitude: .infinity),
      Coordinate(latitude: 91, longitude: 126.978),
      Coordinate(latitude: 37.5665, longitude: -181),
    ]
  )
  func ignoresInvalidCoordinate(coordinate: Coordinate) throws {
    let busanPhotos = photos("busan", at: busan, days: 2 ... 3, perDay: 5, month: 5)
    let invalid = photos("invalid", at: coordinate, days: 2 ... 2, perDay: 5, month: 5)

    let trips = TravelDetector.trips(in: home + busanPhotos + invalid, calendar: calendar)

    #expect(try #require(trips.only).assetIDs == busanPhotos.map(\.id))
  }

  @Test("위치나 날짜가 없는 이미지는 판정에 쓰지 않는다")
  func ignoresAssetsWithoutLocationOrDate() throws {
    let busanPhotos = photos("busan", at: busan, days: 2 ... 3, perDay: 5, month: 5)
    let withoutLocation = ImageAsset(
      id: "screenshot",
      creationDate: date(month: 5, day: 2, hour: 15),
      coordinate: nil,
      pixelWidth: 1170,
      pixelHeight: 2532,
      isScreenshot: true
    )
    let withoutDate = ImageAsset(
      id: "undated",
      creationDate: nil,
      coordinate: busan,
      pixelWidth: 4032,
      pixelHeight: 3024,
      isScreenshot: false
    )

    let trips = TravelDetector.trips(in: home + busanPhotos + [withoutLocation, withoutDate], calendar: calendar)

    #expect(try #require(trips.only).assetIDs == busanPhotos.map(\.id))
    #expect(TravelDetector.trips(in: [], calendar: calendar).isEmpty)
  }
}

private let seoul = Coordinate(latitude: 37.5665, longitude: 126.978)
private let busan = Coordinate(latitude: 35.1796, longitude: 129.0756)
private let jeju = Coordinate(latitude: 33.4996, longitude: 126.5312)
private let daejeon = Coordinate(latitude: 36.3504, longitude: 127.3845)

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
  return calendar
}()

/// 1~4월 매일 한 장씩 서울에서 찍은 일상 사진.
private let home = (1 ... 4).flatMap { month in (1 ... 28).map { photo(
  "home-\(month)-\($0)",
  at: seoul,
  month: month,
  day: $0
) } }

private func date(month: Int, day: Int, hour: Int) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private func photo(_ id: String, at coordinate: Coordinate, month: Int, day: Int, hour: Int = 12) -> ImageAsset {
  ImageAsset(
    id: id,
    creationDate: date(month: month, day: day, hour: hour),
    coordinate: coordinate,
    pixelWidth: 4032,
    pixelHeight: 3024,
    isScreenshot: false
  )
}

/// 하루에 `perDay` 장씩 10시부터 1분 간격으로 찍은 사진.
private func photos(
  _ prefix: String,
  at coordinate: Coordinate,
  days: ClosedRange<Int>,
  perDay: Int,
  month: Int
) -> [ImageAsset] {
  days.flatMap { day in
    (0 ..< perDay).map { index in
      ImageAsset(
        id: "\(prefix)-\(day)-\(index)",
        creationDate: date(month: month, day: day, hour: 10).addingTimeInterval(Double(index) * 60),
        coordinate: coordinate,
        pixelWidth: 4032,
        pixelHeight: 3024,
        isScreenshot: false
      )
    }
  }
}

private extension Array {
  var only: Element? {
    count == 1 ? first : nil
  }
}
