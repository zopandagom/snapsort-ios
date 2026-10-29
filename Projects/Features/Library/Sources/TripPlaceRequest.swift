import Core
import Foundation
import MapInterface
import PhotoStoreInterface

// 여행 폴더 상세의 이름 요청 보조 타입 (`TripDetailModel`).

extension TripDetailModel {
  /// 이름 응답을 기다리는 시간. 넘으면 이름 없이 기간을 제목으로 보인다(요청은 계속 가고 끝나면 캐시에 쓴다).
  /// 미리 받기와 같은 값이다(`PlaceNameTiming.timeout`, 임시 값).
  static let defaultPlaceNameTimeout = PlaceNameTiming.timeout
}

/// 이름 루프에 넣는 요청. 캐시를 읽은 로캘로 묻는다.
struct TripPlaceRequest: Hashable {
  let key: RoundedCoordinate
  let localeIdentifier: String
}

/// 진행 중인 이름 요청.
struct TripPlaceInFlight {
  /// 요청마다 오르는 번호. 끝난 요청이 그 뒤에 시작한 요청을 비우지 않게 한다.
  let token: Int
  let request: TripPlaceRequest
  let startedAt: ContinuousClock.Instant
  let task: Task<TripPlaceOutcome, Never>
}

enum TripPlaceOutcome {
  /// 응답을 받았다. 항목이 없으면(placemarkNotFound) nil.
  case found(PlaceInfo?)
  /// 요청이 실패했거나 시한을 넘겼다.
  case failed

  /// 요청 결과와 시한 중 먼저 오는 것. 시한이면 `.failed` 다. 부른 Task 가 취소되면(화면이 닫힘) nil 을 바로 돌려준다.
  /// 요청 Task 는 취소하지 않는다(취소해도 요청은 끝나지 않는다).
  static func first(
    of task: Task<TripPlaceOutcome, Never>,
    until deadline: ContinuousClock.Instant
  ) async -> TripPlaceOutcome? {
    let (outcomes, continuation) = AsyncStream.makeStream(
      of: TripPlaceOutcome.self,
      bufferingPolicy: .bufferingOldest(1)
    )
    Task { await continuation.yield(task.value) }
    let timer = Task {
      try? await Task.sleep(until: deadline, clock: .continuous)
      guard !Task.isCancelled else { return }
      continuation.yield(.failed)
    }
    defer {
      timer.cancel()
      continuation.finish()
    }
    var iterator = outcomes.makeAsyncIterator()
    return await iterator.next()
  }
}

/// 이름 루프가 기다리는 요청. 진입 번호가 같고 기다림이 끝나지 않았을 때만 같은 요청의 다음 신호를 건너뛴다.
struct TripPlaceWait {
  let generation: Int
  /// 기다림마다 오르는 번호. 멈춘 지난 기다림이 끝나며 지금 기다림을 비우지 않게 한다.
  let token: Int
  let request: TripPlaceRequest
}

extension CachedPlaceName {
  /// 같은 뜻의 화면 상태.
  var state: TripPlaceNameState {
    switch self {
    case let .named(name): .named(name)
    case .unnamed: .unnamed
    }
  }
}
