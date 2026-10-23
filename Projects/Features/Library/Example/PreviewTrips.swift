import Core
import Foundation
import LibraryFeature
import MapInterface
import MapTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI

/// Example 의 여행 폴더 데모. 세 여행이 장소 이름의 세 경우를 보인다:
/// - 제주: 이름·시간대가 캐시돼 있어 묻지 않고 바로 보인다.
/// - 도쿄: 캐시가 없어 상세를 열면 "장소 확인 중"을 거쳐 1.5초 뒤 이름이 보인다.
/// - 태평양: 응답에 쓸 이름이 없어 기간을 제목으로 쓴다(시간대만 받는다).
/// 제주는 사진 두 장이 저장소에 없어(보관함에서 지워진 것처럼) 상세에 안내 줄이 보이고, 각 여행 기간에 영수증·지도·문서 캡처가 있다.
/// 여행 영수증 여섯 장은 영수증 목록에도 보인다(`receiptValues`).
enum PreviewTrips {
  static let jejuCenter = Coordinate(latitude: 33.4996, longitude: 126.5312)
  static let tokyoCenter = Coordinate(latitude: 35.6812, longitude: 139.7614)
  static let pacificCenter = Coordinate(latitude: 0, longitude: -150)

  static let jeju = Trip(
    assetIDs: (0 ..< 12).map { PreviewTrips.photoID("jeju", $0) },
    startDate: .previewSeoul(2026, 7, 10, hour: 9),
    endDate: .previewSeoul(2026, 7, 12, hour: 18),
    center: PreviewTrips.jejuCenter
  )

  static let tokyo = Trip(
    assetIDs: (0 ..< 8).map { PreviewTrips.photoID("tokyo", $0) },
    startDate: .previewSeoul(2026, 8, 1, hour: 10),
    endDate: .previewSeoul(2026, 8, 3, hour: 20),
    center: PreviewTrips.tokyoCenter
  )

  static let pacific = Trip(
    assetIDs: (0 ..< 5).map { PreviewTrips.photoID("pacific", $0) },
    startDate: .previewSeoul(2026, 3, 5, hour: 6),
    endDate: .previewSeoul(2026, 3, 6, hour: 15),
    center: PreviewTrips.pacificCenter
  )

  static let trips = [PreviewTrips.jeju, PreviewTrips.tokyo, PreviewTrips.pacific]

  /// 저장소에 없는(보관함에서 지워진) 제주 사진.
  static let missingIDs: Set<ImageAsset.ID> = [PreviewTrips.photoID("jeju", 10), PreviewTrips.photoID("jeju", 11)]

  /// 시드 캐시의 이름이 캐시된 로캘. Model 이 캐시를 읽을 때 쓰는 기기 로캘 식별자(`Locale.current.identifier`)와 같게 둔다
  /// (다르면 이름이 다른 로캘로 캐시된 것으로 보여 목록에 안 보이고 상세를 열 때 다시 묻는다).
  static let placesLocaleIdentifier = Locale.current.identifier

  /// 제주만 이름·시간대가 캐시돼 있다(`placesLocaleIdentifier` 로 캐시한 것으로 본다).
  static let places: [RoundedCoordinate: CachedPlace] = {
    guard let key = RoundedCoordinate(PreviewTrips.jejuCenter) else { return [:] }
    return [key: CachedPlace(name: .named("제주특별자치도 제주시"), timeZoneIdentifier: "Asia/Seoul")]
  }()

  static func photoID(_ trip: String, _ index: Int) -> ImageAsset.ID {
    "trip-\(trip)-\(index)"
  }

  /// 여행 영수증의 가게·금액(지어낸 값). 여행마다 가운데 시각과 30분 뒤의 두 장이다.
  static let receiptValues: [ImageAsset.ID: ReceiptInfo] = [
    PreviewTrips.captureID(0, 0): .preview("제주 흑돼지", krw: 48000),
    PreviewTrips.captureID(0, 1): .preview("제주 카페", krw: 6500),
    PreviewTrips.captureID(1, 0): .preview("ローソン 新宿店", minorUnits: 980, currency: .jpy),
    PreviewTrips.captureID(1, 1): .preview("ファミリーマート", minorUnits: 1520, currency: .jpy),
    PreviewTrips.captureID(2, 0): .preview("ALOHA MART", minorUnits: 2340, currency: .usd),
    PreviewTrips.captureID(2, 1): .preview("ALOHA MART", minorUnits: 1200, currency: .usd),
  ]

  /// 여행 사진(저장소에 없는 것 제외)과 여행 기간의 캡처. `receiptsChecking` 이면 여행 영수증이 추출 대기다.
  static func images(receiptsChecking: Bool = false) -> [IndexedImage] {
    let photos = self.trips.flatMap { trip in
      let span = trip.endDate.timeIntervalSince(trip.startDate)
      return trip.assetIDs.enumerated().compactMap { index, id -> IndexedImage? in
        guard !self.missingIDs.contains(id) else { return nil }
        let date = trip.startDate.addingTimeInterval(span * Double(index) / Double(max(trip.assetIDs.count - 1, 1)))
        return IndexedImage(
          asset: .stub(id: id, creationDate: date, coordinate: trip.center),
          labels: [],
          textRecognition: .notNeeded,
          categories: [.landscape]
        )
      }
    }
    return photos + self.captures(receiptsChecking: receiptsChecking)
  }

  /// 각 여행 기간 가운데쯤의 영수증 둘·지도·문서 캡처. 지도 캡처는 캡처 묶음을 추출했고 지역이 없다(지역 모름).
  private static func captures(receiptsChecking: Bool) -> [IndexedImage] {
    self.trips.enumerated().flatMap { tripIndex, trip in
      let middle = trip.startDate.addingTimeInterval(trip.endDate.timeIntervalSince(trip.startDate) / 2)
      let categories: [ImageCategory] = [.receipt, .receipt, .map, .document]
      return categories.enumerated().map { index, category in
        let id = self.captureID(tripIndex, index)
        return IndexedImage(
          asset: .stub(
            id: id,
            creationDate: middle.addingTimeInterval(Double(index) * 1800),
            pixelWidth: 1179,
            pixelHeight: 2556,
            isScreenshot: true
          ),
          labels: [],
          textRecognition: .recognized([]),
          categories: [category],
          receipt: receiptsChecking ? nil : self.receiptValues[id],
          captureGroups: category == .map ? .empty : nil
        )
      }
    }
  }

  private static func captureID(_ tripIndex: Int, _ index: Int) -> ImageAsset.ID {
    "trip-capture-\(tripIndex)-\(index)"
  }

  /// 보관함 대역이 읽을 여행 사진·캡처 식별자(저장소에 없는 것 포함).
  static var imageIDs: [ImageAsset.ID] {
    self.trips.flatMap(\.assetIDs) + self.trips.indices.flatMap { tripIndex in
      (0 ..< 4).map { self.captureID(tripIndex, $0) }
    }
  }

  /// 도쿄는 1.5초 뒤 이름·시간대를, 태평양은 시간대만 돌려준다. `failing` 이면 모든 요청이 실패한다.
  /// - Parameter openResult: 주소로 지도 앱 열기의 결과(캡처 행동 데모가 함께 쓴다).
  static func map(failing: Bool = false, openResult: Bool = true) -> MapClientFake {
    var results: [RoundedCoordinate: Result<PlaceInfo?, PlaceNameError>] = [:]
    if let tokyo = RoundedCoordinate(self.tokyoCenter), let pacific = RoundedCoordinate(self.pacificCenter) {
      results[tokyo] = failing ? .failure(.failed) : .success(PlaceInfo(
        name: "일본 도쿄 지요다구",
        timeZoneIdentifier: "Asia/Tokyo"
      ))
      results[pacific] = failing ? .failure(.failed) : .success(PlaceInfo(name: nil, timeZoneIdentifier: "GMT-1000"))
    }
    if failing, let jeju = RoundedCoordinate(self.jejuCenter) {
      results[jeju] = .failure(.failed)
    }
    return MapClientFake(
      openResult: openResult,
      placeNameResults: results,
      onPlaceName: { _ in try? await Task.sleep(for: .seconds(1.5)) }
    )
  }
}

extension Date {
  static func previewSeoul(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
  }
}

@MainActor
private func tripListPreview(photoStore: PhotoStoreClientFake) -> some View {
  NavigationStack {
    TripListView(
      model: TripListModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore),
      categoryModel: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore)
    )
  }
}

@MainActor
private func tripDetailPreview(trip: Trip) -> some View {
  let photoStore = PhotoStoreClientFake.previewClassified()
  return NavigationStack {
    TripDetailView(
      model: TripDetailModel(photoStore: photoStore, map: PreviewTrips.map()),
      categoryModel: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore),
      trip: trip
    )
  }
}

#Preview("여행 - 목록") {
  tripListPreview(photoStore: PhotoStoreClientFake.previewClassified())
}

#Preview("여행 - 빈 목록") {
  tripListPreview(photoStore: PhotoStoreClientFake.previewClassified(includesTrips: false))
}

#Preview("여행 - 상세") {
  tripDetailPreview(trip: PreviewTrips.tokyo)
}

#Preview("여행 - 사라짐") {
  // 사진이 겹치는 저장된 여행이 없다(판정이 바뀌어 여행이 사라진 경우).
  tripDetailPreview(trip: Trip(
    assetIDs: ["gone-0"],
    startDate: .previewSeoul(2026, 5, 1, hour: 9),
    endDate: .previewSeoul(2026, 5, 2, hour: 9),
    center: PreviewTrips.jejuCenter
  ))
}
