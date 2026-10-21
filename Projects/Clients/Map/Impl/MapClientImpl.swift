import Core
import Foundation
import MapInterface
import UIKit

/// 지도 앱 URL(`maps://`)로 여는 구현과 MapKit 역지오코딩 (docs/ARCHITECTURE.md §4 위치·지도).
/// 주소를 지오코딩하지 않고 지도 앱의 검색어로 넘긴다. 역지오코딩에는 반올림 좌표만 보낸다.
/// 주소·URL·좌표·장소 이름은 로그에 남기지 않는다.
public struct MapClientImpl: MapClient {
  typealias Geocode = @Sendable (Coordinate, Locale) async throws(PlaceNameError) -> [PlaceAddress]

  /// 쿼리 값에서 그대로 두는 글자: RFC 3986 unreserved. 나머지는 모두 퍼센트 인코딩한다.
  private static let unreserved = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
  )

  private let geocode: Geocode

  public init() {
    self.init { coordinate, locale throws(PlaceNameError) in
      try await ReverseGeocoder.addresses(near: coordinate, locale: locale)
    }
  }

  /// 테스트가 MapKit 대신 주입한다.
  init(geocode: @escaping Geocode) {
    self.geocode = geocode
  }

  public func openInMaps(address: String) async -> Bool {
    guard let url = Self.mapsURL(address: address) else {
      return false
    }
    return await Self.open(url)
  }

  /// `maps://?q=<주소>`. 앞뒤 공백을 지우고, 비면 nil. 쿼리 값은 RFC 3986 unreserved 밖을 모두 퍼센트 인코딩한다
  /// (`URLComponents` 는 "+"·"?" 를 그대로 둬 "+" 가 공백으로 읽힐 수 있다).
  static func mapsURL(address: String) -> URL? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let query = trimmed.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else {
      return nil
    }
    return URL(string: "maps://?q=\(query)")
  }

  public func placeName(near coordinate: RoundedCoordinate, locale: Locale) async throws(PlaceNameError) -> PlaceInfo? {
    // 정수(×100)에서 만든 좌표만 보낸다.
    let addresses = try await self.geocode(coordinate.coordinate, locale)
    guard let first = addresses.first else {
      return nil
    }
    return PlaceInfo(name: Self.placeName(from: addresses), timeZoneIdentifier: first.timeZoneIdentifier)
  }

  /// 항목 순서대로, 앞뒤 공백을 지우고 빈 문자열은 없는 것으로 보아 cityWithContext → cityName → regionName 중 처음 값.
  /// `MKMapItem.name` 은 쓰지 않는다(POI·거리 주소·우편번호가 온다, 실측).
  static func placeName(from addresses: [PlaceAddress]) -> String? {
    for address in addresses {
      for field in [address.cityWithContext, address.cityName, address.regionName] {
        if let value = field?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
          return value
        }
      }
    }
    return nil
  }

  @MainActor
  private static func open(_ url: URL) async -> Bool {
    await UIApplication.shared.open(url)
  }
}
