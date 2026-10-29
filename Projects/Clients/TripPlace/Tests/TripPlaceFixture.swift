import Core
import Foundation
import MapInterface
import MapTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
@testable import TripPlaceImpl

/// 테스트 시계. `now()` 는 테스트가 옮기는 시각이고, 수면은 부르는 쪽(간격·시한)별로 정한 동작을 한다.
/// 실제 3초·15초·10분을 기다리지 않는다. 기본은 간격은 바로 돌아오고 시한은 취소될 때까지 매달린다
/// (응답이 늘 시한보다 먼저 이긴다). 여러 Task 에서 부르므로 Mutex 로 보호한다.
final class TestTiming: Sendable {
  enum Behavior: Sendable {
    case immediate
    /// 취소될 때까지 매달린다(취소되면 던진다).
    case hang
    /// 문이 열릴 때까지 기다린다.
    case wait(Gate)
  }

  private let base = ContinuousClock.now
  private let state: Mutex<State>

  private struct State {
    var offset: Duration = .zero
    var sleeps: [(TripPlaceSleep, Duration)] = []
    var interval: Behavior
    var timeout: Behavior
  }

  init(interval: Behavior = .immediate, timeout: Behavior = .hang) {
    self.state = Mutex(State(interval: interval, timeout: timeout))
  }

  func now() -> ContinuousClock.Instant {
    self.base + self.state.withLock { $0.offset }
  }

  func advance(by duration: Duration) {
    self.state.withLock { $0.offset += duration }
  }

  func setInterval(_ behavior: Behavior) {
    self.state.withLock { $0.interval = behavior }
  }

  func setTimeout(_ behavior: Behavior) {
    self.state.withLock { $0.timeout = behavior }
  }

  /// 그 쪽 수면에 넘긴 시간을 부른 순서대로.
  func sleeps(_ kind: TripPlaceSleep) -> [Duration] {
    self.state.withLock { $0.sleeps.filter { $0.0 == kind }.map(\.1) }
  }

  func sleep(_ kind: TripPlaceSleep, _ duration: Duration) async throws {
    let behavior = self.state.withLock { state in
      state.sleeps.append((kind, duration))
      return kind == .interval ? state.interval : state.timeout
    }
    switch behavior {
    case .immediate:
      return
    case .hang:
      try await Task.sleep(for: .seconds(3600))
    case let .wait(gate):
      await gate.wait()
      try Task.checkCancellation()
    }
  }
}

/// 테스트가 열 때까지 기다리게 하는 문. 기다리는 Task 가 취소되면 바로 돌아온다.
final class Gate: Sendable {
  private let isOpen = Mutex(false)

  func open() {
    self.isOpen.withLock { $0 = true }
  }

  func wait() async {
    while !self.isOpen.withLock({ $0 }), !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(1))
    }
  }
}

/// 장소 이름 요청이 동시에 몇 개 나가 있는지 센다. `MapClientFake(onPlaceName:)` 안에서 부른다.
final class ConcurrencyProbe: Sendable {
  private let state = Mutex((current: 0, maximum: 0))

  var maximum: Int {
    self.state.withLock { $0.maximum }
  }

  func enter() {
    self.state.withLock { state in
      state.current += 1
      state.maximum = max(state.maximum, state.current)
    }
  }

  func leave() {
    self.state.withLock { $0.current -= 1 }
  }
}

/// `placeChanges()` 를 구독해 받은 신호를 센다. 끝나면 `cancel()` 한다.
final class ChangeCounter: Sendable {
  private let count = Mutex(0)
  private let task = Mutex<Task<Void, Never>?>(nil)

  init(_ client: TripPlaceClientImpl) async {
    let changes = await client.placeChanges()
    let task = Task {
      for await _ in changes {
        self.count.withLock { $0 += 1 }
      }
    }
    self.task.withLock { $0 = task }
  }

  var value: Int {
    self.count.withLock { $0 }
  }

  func cancel() {
    self.task.withLock { $0?.cancel() }
  }
}

enum TripPlaceFixture {
  static let locale = Locale(identifier: "ko_KR")

  /// 시작이 day 일째인 하루짜리 여행. 중심점은 (latitude, 127).
  static func trip(day: Int, latitude: Double) -> Trip {
    let start = Date(timeIntervalSince1970: TimeInterval(day) * 86400)
    return Trip(
      assetIDs: ["trip-\(day)"],
      startDate: start,
      endDate: start.addingTimeInterval(3600),
      center: Coordinate(latitude: latitude, longitude: 127)
    )
  }

  static func key(_ trip: Trip) throws -> RoundedCoordinate {
    try #require(trip.placeKey)
  }

  static func client(
    map: MapClientFake,
    store: PhotoStoreClientFake,
    timing: TestTiming = TestTiming(),
    policy: TripPlacePolicy = TripPlacePolicy(),
    isLowPowerMode: Bool = false
  ) -> TripPlaceClientImpl {
    TripPlaceClientImpl(
      map: map,
      photoStore: store,
      policy: policy,
      now: { timing.now() },
      sleep: { kind, duration in try await timing.sleep(kind, duration) },
      isLowPowerMode: { isLowPowerMode }
    )
  }

  /// 이름을 "이름-<위도 정수>" 로 돌려주는 결과.
  static func namedResults(_ trips: [Trip]) throws -> [RoundedCoordinate: Result<PlaceInfo?, PlaceNameError>] {
    var results: [RoundedCoordinate: Result<PlaceInfo?, PlaceNameError>] = [:]
    for trip in trips {
      try results[self.key(trip)] = .success(PlaceInfo(name: self.name(trip), timeZoneIdentifier: "Asia/Tokyo"))
    }
    return results
  }

  static func name(_ trip: Trip) -> String {
    "이름-\(Int(trip.center.latitude))"
  }
}

/// 조건이 될 때까지 짧게 잠들며 기다린다. 요청 Task·경주 Task 는 전역 실행기에서 돌아 끝나는 시점이 스케줄링에 달렸으므로
/// 반복 횟수가 아니라 시간으로 제한한다(LibraryModelTests 의 같은 함수와 같은 방식).
func waitUntil(timeout: Duration = .seconds(30), _ condition: () -> Bool) async {
  let deadline = ContinuousClock.now + timeout
  while !condition(), ContinuousClock.now < deadline {
    do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
  }
  #expect(condition(), "기다리던 상태가 되지 않았다")
}
