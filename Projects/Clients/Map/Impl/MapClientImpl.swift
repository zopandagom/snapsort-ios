import Foundation
import MapInterface
import UIKit

/// 지도 앱 URL(`maps://`)로 여는 구현. 주소를 지오코딩하지 않고 지도 앱의 검색어로 넘긴다 (docs/ARCHITECTURE.md §4 위치·지도).
/// 주소·URL 은 로그에 남기지 않는다.
public struct MapClientImpl: MapClient {
  /// 쿼리 값에서 그대로 두는 글자: RFC 3986 unreserved. 나머지는 모두 퍼센트 인코딩한다.
  private static let unreserved = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
  )

  public init() {}

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

  @MainActor
  private static func open(_ url: URL) async -> Bool {
    await UIApplication.shared.open(url)
  }
}
