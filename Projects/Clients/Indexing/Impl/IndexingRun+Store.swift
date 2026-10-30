import Core
import Foundation
import IndexingInterface
import PhotoStoreInterface

/// 실행의 저장소 호출 (docs/ARCHITECTURE.md §4 인덱싱). 저장소 호출은 모두 `store` 로 실행의 문(`gate`)을 거친다.
extension IndexingRun {
  func delete(_ ids: Set<ImageAsset.ID>) async throws(IndexingStop) {
    let ids = ids.sorted()
    for start in stride(from: 0, to: ids.count, by: self.batchSize) {
      let batch = Set(ids[start ..< min(start + self.batchSize, ids.count)])
      try await self
        .store(write: true) { () async throws(PhotoStoreError) in try await self.photoStore.delete(ids: batch) }
    }
  }

  /// 여행 판정은 메타데이터만 보므로 분석을 기다리지 않고 보관함이 바뀔 때마다 전체를 다시 판정한다.
  /// 이미 반영한 변경이 다시 와서 보관함이 그대로면 다시 판정·저장하지 않는다.
  mutating func replaceTripsIfChanged() async throws(IndexingStop) {
    guard self.assets != self.judgedAssets else { return }
    let trips = TravelDetector.trips(in: Array(self.assets.values), calendar: self.calendar)
    // 여행 교체는 쓰기 표시에 넣지 않는다: 실행의 첫 비교가 늘 부르고(`judgedAssets` 가 nil) 위젯(기프티콘 만료 요약)과 무관하다.
    try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.replaceTrips(trips) }
    self.judgedAssets = self.assets
  }

  /// 저장소를 문 확인으로 감싸 부른다. 닫힌 문이면 부르지 않고 `.cancelled`(실행을 멈춘 것)를 던진다.
  /// 쓰기 호출(`write`)이 성공하면 문에 알린다(BG 실행이 저장소를 바꿨는지, 위젯 갱신 요청 조건. 여행 교체는 넣지 않는다).
  func store<Output>(
    write: Bool = false,
    _ operation: () async throws(PhotoStoreError) -> Output
  ) async throws(IndexingStop) -> Output {
    guard self.gate.enter() else { throw .cancelled }
    defer { self.gate.exit() }
    do {
      let output = try await operation()
      if write {
        self.gate.didWrite()
      }
      return output
    } catch {
      throw .storeFailed
    }
  }

  /// 저장 수는 보관함에 있는 것만 센다. 2단계 `notFound` 뒤 그 삭제 변경보다 새 사진 추가가 먼저 반영돼도
  /// 저장 수가 전체 수를 넘어 새 사진을 분류하기 전에 1단계를 마친 것처럼 보이지 않게 한다.
  var progress: IndexingProgress {
    IndexingProgress(
      totalCount: self.assets.count,
      indexedCount: self.indexedIDs.count { self.assets[$0] != nil },
      skippedCount: self.skippedIDs.count,
      pendingTextCount: self.pendingTextIDs.count,
      recognizedTextCount: self.recognizedTextCount,
      skippedTextCount: self.textSkippedIDs.count
    )
  }
}
