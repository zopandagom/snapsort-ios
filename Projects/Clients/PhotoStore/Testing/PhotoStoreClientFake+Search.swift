import Core
import PhotoStoreInterface

// 검색 목록 (docs/ARCHITECTURE.md §4 저장소·검색).
public extension PhotoStoreClientFake {
  /// `searchEntries()` 를 부른 횟수. `searchEntriesErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var searchEntriesCallCount: Int {
    self.state.withLock { $0.search.entriesCallCount }
  }

  /// Impl 과 같은 표: 글자를 읽은 이미지만 최신순(생성일 없으면 뒤, 같으면 식별자 순)으로, 대기 수는 `.pending` 이미지 수.
  func searchEntries() async throws(PhotoStoreError) -> SearchEntries {
    try self.throwIfNeeded()
    let (index, result) = self.state.withLock { state in
      defer { state.search.entriesCallCount += 1 }
      let entries = state.images.values
        .filter { $0.textLines != nil }
        .sorted(by: Self.isNewer)
        .map { image in
          SearchEntry(
            asset: image.asset,
            lines: (image.textLines ?? []).map(\.text),
            captureGroups: image.captureGroups
          )
        }
      let pending = state.images.values.count { $0.textRecognition == .pending }
      return (state.search.entriesCallCount, SearchEntries(entries: entries, pendingTextCount: pending))
    }
    if let error = self.searchOptions.entriesErrors[index] {
      throw error
    }
    await self.searchOptions.onEntries(index)
    return result
  }
}

extension PhotoStoreClientFake {
  /// 검색 목록 읽기용 실패·훅.
  struct SearchOptions {
    /// `searchEntries()` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
    /// `error`(모든 호출)가 정해져 있으면 그것이 먼저다.
    let entriesErrors: [Int: PhotoStoreError]
    /// `searchEntries()` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
    /// 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
    let onEntries: @Sendable (Int) async -> Void
  }

  /// 검색 목록용 기록.
  struct SearchState {
    var entriesCallCount = 0
  }
}
