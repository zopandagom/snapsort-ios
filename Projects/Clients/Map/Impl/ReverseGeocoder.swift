import Core
import Foundation
import MapInterface
import MapKit

/// 역지오코딩 응답 항목에서 쓰는 값.
struct PlaceAddress: Sendable, Equatable {
  var cityWithContext: String?
  var cityName: String?
  var regionName: String?
  /// `MKMapItem.timeZone` 식별자.
  var timeZoneIdentifier: String?
}

/// `MKReverseGeocodingRequest` 로 묻는다 (docs/ARCHITECTURE.md §4 위치·지도). 좌표·결과는 로그에 남기지 않는다.
enum ReverseGeocoder {
  /// 요청을 만들지 못하면 failed. 항목이 없으면(`placemarkNotFound`) [], 그 밖의 오류는 failed.
  /// 진행 중 `cancel()` 을 부르면 응답이 영영 오지 않으므로(실측) 부르지 않는다. Task 취소도 요청이 받지 않아 끝까지 간다.
  @MainActor
  static func addresses(near coordinate: Coordinate, locale: Locale) async throws(PlaceNameError) -> [PlaceAddress] {
    guard let request = MKReverseGeocodingRequest(
      location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    ) else {
      throw .failed
    }
    request.preferredLocale = locale
    do {
      return try await request.mapItems.map { item in
        PlaceAddress(
          cityWithContext: item.addressRepresentations?.cityWithContext,
          cityName: item.addressRepresentations?.cityName,
          regionName: item.addressRepresentations?.regionName,
          timeZoneIdentifier: item.timeZone?.identifier
        )
      }
    } catch {
      if self.isNotFound(error) {
        return []
      }
      throw .failed
    }
  }

  /// `MKError.placemarkNotFound`(브리징된 NSError 포함)인지.
  static func isNotFound(_ error: any Error) -> Bool {
    let error = error as NSError
    return error.domain == MKErrorDomain && error.code == Int(MKError.Code.placemarkNotFound.rawValue)
  }
}
