import Core
import PhotoStoreInterface

// 보관함 화면 카드의 대표 사진 (docs/ARCHITECTURE.md §4 카테고리 화면·저장소).
public extension PhotoStoreClientFake {
  /// `categoryCovers(limit:)` 를 부른 횟수. `categoryCoversErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var categoryCoversCallCount: Int {
    self.state.withLock { $0.cover.callCount }
  }

  /// Impl 과 같은 표: 이미지 카테고리는 `assets(in:)` 순서의 앞 `limit` 장, 여행은 최근 여행 `limit` 개마다
  /// `Trip.coverCandidateIDs` 중 저장소에 있는 첫 장(없으면 그 여행을 건너뛴다). 대표가 없는 카테고리는 빠진다.
  func categoryCovers(limit: Int) async throws(PhotoStoreError) -> [ImageCategory: [ImageAsset.ID]] {
    try self.throwIfNeeded()
    let (index, result) = self.state.withLock { state in
      defer { state.cover.callCount += 1 }
      return (state.cover.callCount, Self.covers(of: state, limit: limit))
    }
    if let error = self.coverOptions.errors[index] {
      throw error
    }
    await self.coverOptions.onCovers(index)
    return result
  }
}

extension PhotoStoreClientFake {
  /// 대표 사진 조회용 실패·훅.
  struct CoverOptions {
    /// `categoryCovers(limit:)` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
    /// `error`(모든 호출)가 정해져 있으면 그것이 먼저다.
    let errors: [Int: PhotoStoreError]
    /// `categoryCovers(limit:)` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
    /// 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
    let onCovers: @Sendable (Int) async -> Void
  }

  /// 대표 사진 조회용 기록.
  struct CoverState {
    var callCount = 0
  }

  /// 잠금 안에서 부르므로 `images` 처럼 잠금을 다시 잡는 속성을 쓰지 않는다.
  private static func covers(of state: State, limit: Int) -> [ImageCategory: [ImageAsset.ID]] {
    guard limit > 0 else {
      return [:]
    }
    var covers: [ImageCategory: [ImageAsset.ID]] = [:]
    for category in ImageCategory.allCases where category != .travel {
      let ids = Self.sortedImages(state.images.values, in: category).prefix(limit).map(\.id)
      if !ids.isEmpty {
        covers[category] = ids
      }
    }
    let tripCovers = state.trips
      .sorted { lhs, rhs in
        if lhs.startDate != rhs.startDate {
          return lhs.startDate > rhs.startDate
        }
        return lhs.endDate > rhs.endDate
      }
      .prefix(limit)
      .compactMap { trip in trip.coverCandidateIDs.first { state.images[$0] != nil } }
    if !tripCovers.isEmpty {
      covers[.travel] = tripCovers
    }
    return covers
  }
}
