import Core
import Foundation
import MapInterface
import PhotoStoreInterface

// 미리 받기의 요청 하나: 요청 Task(회차 수명과 떨어져 끝까지 간다)와 응답·시한 경주, 보조 타입 (`TripPlaceClientImpl`).

extension TripPlaceClientImpl {
  /// 요청 Task 를 시작하고 나간 요청으로 둔다. Task 는 actor 격리라 이 함수가 돌아온 뒤에야 돈다.
  func startRequest(_ request: TripPlaceRequest) -> TripPlaceOutstanding {
    let token = self.issueToken()
    let task = Task { await self.perform(request, token: token) }
    let outstanding = TripPlaceOutstanding(token: token, request: request, startedAt: self.now(), task: task)
    self.setOutstanding(outstanding)
    return outstanding
  }

  /// 요청 Task 본문. 받은 것을 캐시에 쓰고 끝낸다. 회차가 이미 끝났어도(시한·취소) 같게 처리해 늦은 응답도 쓰고 알린다.
  private func perform(_ request: TripPlaceRequest, token: Int) async -> TripPlaceRequestOutcome {
    let outcome: TripPlaceRequestOutcome
    do {
      let info = try await self.map.placeName(
        near: request.key,
        locale: Locale(identifier: request.localeIdentifier)
      )
      if let info {
        outcome = await self.save(info, for: request)
      } else {
        // 항목 없음은 캐시하지 않는다(기존 규칙). 같은 실행 동안만 다시 묻지 않는다.
        outcome = .notFound
      }
    } catch {
      outcome = .failed
    }
    self.finishRequest(request, token: token, outcome: outcome)
    return outcome
  }

  private func save(_ info: PlaceInfo, for request: TripPlaceRequest) async -> TripPlaceRequestOutcome {
    do {
      let saved = try await self.photoStore.savePlace(
        info.name.map(CachedPlaceName.named) ?? .unnamed,
        timeZoneIdentifier: info.timeZoneIdentifier,
        for: request.key,
        localeIdentifier: request.localeIdentifier
      )
      // false 는 그사이 사진을 지워 여행이 사라진 것이다. 쓰지 않았으니 알리지 않는다.
      return saved ? .saved : .tripGone
    } catch {
      return .saveFailed
    }
  }

  /// 요청 결과·시한 중 먼저 오는 것. 부른 Task 가 취소되면 nil 을 바로 돌려준다.
  /// 요청 Task 는 취소하지 않는다(MapKit 요청은 취소를 받지 않고, `cancel()` 하면 돌아오지 않는다).
  /// `withTaskGroup` 은 `task.value` 기다림이 취소를 받지 않아 그룹이 끝나지 않으므로 쓰지 않는다.
  func first(
    of task: Task<TripPlaceRequestOutcome, Never>,
    timeout: Duration
  ) async -> TripPlaceRaceResult? {
    let (results, continuation) = AsyncStream.makeStream(
      of: TripPlaceRaceResult.self,
      bufferingPolicy: .bufferingOldest(1)
    )
    Task { await continuation.yield(.response(task.value)) }
    let timer = Task { [sleep = self.sleep] in
      try? await sleep(.timeout, timeout)
      guard !Task.isCancelled else { return }
      continuation.yield(.timedOut)
    }
    defer {
      timer.cancel()
      continuation.finish()
    }
    var iterator = results.makeAsyncIterator()
    return await iterator.next()
  }
}

/// 정책 값. 모두 임시 값이다(실기기 한도·오프라인 동작을 확인하지 못했다).
struct TripPlacePolicy {
  /// 앞 요청이 끝난 뒤 다음 요청까지의 간격(회차를 넘어 앱 전체).
  var requestInterval: Duration = .seconds(3)
  /// 실패·시한 뒤 다음 회차까지의 최소 간격.
  var failureCooldown: Duration = .seconds(600)
  /// 회차 하나에서 묻는 키 상한.
  var roundLimit = 30
  /// 한 요청의 시한. 여행 폴더 상세와 같은 값이다.
  var timeout: Duration = PlaceNameTiming.timeout
}

/// 주입한 수면을 부르는 쪽. 테스트가 요청 간격과 시한을 다르게 흉내 낸다.
enum TripPlaceSleep: Sendable {
  case interval
  case timeout
}

/// 미리 받기 요청 하나. 캐시 키와 같은 (반올림 중심점, 로캘) 이다.
struct TripPlaceRequest: Hashable, Sendable {
  let key: RoundedCoordinate
  let localeIdentifier: String
}

/// 나간 요청.
struct TripPlaceOutstanding: Sendable {
  /// 요청마다 오르는 번호. 끝난 요청이 그 뒤에 시작한 요청을 비우지 않게 하고, 시한 쉼의 주인을 가린다.
  let token: Int
  let request: TripPlaceRequest
  let startedAt: ContinuousClock.Instant
  let task: Task<TripPlaceRequestOutcome, Never>
}

enum TripPlaceRequestOutcome: Sendable {
  /// 캐시에 썼다(이름 또는 이름 없음).
  case saved
  /// 응답은 왔지만 그 키의 여행이 사라져 쓰지 않았다.
  case tripGone
  /// 항목 없음(`placemarkNotFound`).
  case notFound
  /// 요청 실패.
  case failed
  /// 저장소에 쓰지 못했다.
  case saveFailed
}

enum TripPlaceRaceResult: Sendable {
  case response(TripPlaceRequestOutcome)
  case timedOut
}
