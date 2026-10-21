import Core
import Foundation
import MapInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 지도 앱을 열지 않고 받은 주소를 기록하고, 장소 이름 요청은 정한 결과를 돌려주며 기록한다.
/// 기록이 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class MapClientFake: MapClient {
  private let openResult: Bool
  private let onOpen: @Sendable () async -> Void
  private let placeNameResults: [RoundedCoordinate: Result<PlaceInfo?, PlaceNameError>]
  private let onPlaceName: @Sendable (Int) async -> Void
  private let state = Mutex(State())

  private struct State {
    var openedAddresses: [String] = []
    var placeNameRequests: [PlaceNameRequest] = []
  }

  /// - Parameters:
  ///   - openResult: `openInMaps` 가 돌려줄 값. false 면 지도 앱을 열지 못한 경우를 흉내 낸다(그래도 주소는 기록한다).
  ///   - onOpen: `openInMaps` 가 주소를 기록한 뒤, 돌려주기 전에 기다려 부른다. 늦게 끝나는 지도 앱 열기를 흉내 낸다.
  ///   - placeNameResults: `placeName(near:locale:)` 가 키별로 돌려줄 결과. 없는 키는 `.success(nil)`(항목 없음)이다.
  ///   - onPlaceName: `placeName(near:locale:)` 가 요청을 기록한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///     늦게 오거나 끝나지 않는 응답을 흉내 낸다.
  public init(
    openResult: Bool = true,
    onOpen: @escaping @Sendable () async -> Void = {},
    placeNameResults: [RoundedCoordinate: Result<PlaceInfo?, PlaceNameError>] = [:],
    onPlaceName: @escaping @Sendable (Int) async -> Void = { _ in }
  ) {
    self.openResult = openResult
    self.onOpen = onOpen
    self.placeNameResults = placeNameResults
    self.onPlaceName = onPlaceName
  }

  /// `openInMaps` 에 넘긴 주소를 부른 순서대로.
  public var openedAddresses: [String] {
    self.state.withLock { $0.openedAddresses }
  }

  /// `placeName(near:locale:)` 요청을 부른 순서대로. 실패한 요청도 든다.
  public var placeNameRequests: [PlaceNameRequest] {
    self.state.withLock { $0.placeNameRequests }
  }

  public func openInMaps(address: String) async -> Bool {
    self.state.withLock { $0.openedAddresses.append(address) }
    await self.onOpen()
    return self.openResult
  }

  public func placeName(near coordinate: RoundedCoordinate, locale: Locale) async throws(PlaceNameError) -> PlaceInfo? {
    let index = self.state.withLock { state in
      state.placeNameRequests.append(PlaceNameRequest(coordinate: coordinate, localeIdentifier: locale.identifier))
      return state.placeNameRequests.count - 1
    }
    await self.onPlaceName(index)
    return try (self.placeNameResults[coordinate] ?? .success(nil)).get()
  }
}

/// `MapClientFake` 가 받은 장소 이름 요청 하나.
public struct PlaceNameRequest: Sendable, Equatable {
  public let coordinate: RoundedCoordinate
  public let localeIdentifier: String

  public init(coordinate: RoundedCoordinate, localeIdentifier: String) {
    self.coordinate = coordinate
    self.localeIdentifier = localeIdentifier
  }
}
