import Core
import Foundation
import IndexingInterface
import PhotoStoreInterface

/// 캡처 묶음 소급 추출 (docs/ARCHITECTURE.md §4 인덱싱).
/// 캡처 묶음 값이 생기기 전에 저장된 쇼핑·대화·지도 이미지(저장소 경량 이전 뒤)나 규칙 버전을 올리기 전에 추출한 이미지를,
/// OCR 없이 저장된 줄로 다시 추출한다. 기프티콘·영수증 소급과 대상 집합이 따로라 서로의 실패가 다른 쪽을 멈추지 않는다.
extension IndexingRun {
  /// 캡처 묶음 소급 대상을 조회한다. 대상 조회만 실패하면 이번 비교에서는 캡처 묶음 소급만 하지 않고 비교·분류는 이어 간다(빈 집합).
  func captureGroupExtractionPendingIDs() async throws(IndexingStop) -> Set<ImageAsset.ID> {
    do throws(IndexingStop) {
      return try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.captureGroupExtractionPendingIDs()
      }
    } catch {
      guard error == .storeFailed else { throw error }
      return []
    }
  }

  /// 캡처 묶음 소급 한 배치를 한다. 배치마다 진행률을 보내지 않고, 대상이 비면(다 마쳤거나 실패로 멈춤) 같은 값의 진행률을 한 번 보낸다
  /// (받는 쪽이 저장소를 다시 읽어 소급한 묶음을 보일 기회. 카테고리·개수는 바뀌지 않는다). `loop` 가 대상이 있을 때만 부르므로
  /// 비는 순간 한 번이다. 취소로 던질 때는 보내지 않는다.
  mutating func extractCaptureGroupBatch(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    try await self.extractNextCaptureGroupBatch()
    if self.pendingCaptureGroupIDs.isEmpty {
      report(self.progress)
    }
  }

  /// 캡처 묶음 소급 대상 중 최신 `batchSize` 장의 저장된 줄로 추출해 묶음 값만 저장한다.
  /// 고른 배치는 저장할 것이 없어도 모두 대상에서 빼서, 저장 행이 없거나 조건이 맞지 않는 이미지로 같은 실행에서 다시 돌지 않는다.
  /// 저장소는 쇼핑·대화·지도·읽음·추출 안 함 행만 바꾸므로, 그 사이 지워졌거나 다시 대기가 된 행에는 쓰지 않는다.
  /// 저장소를 읽거나 쓰지 못하면 던지지 않고 이번 실행의 캡처 묶음 소급만 멈춘다. 취소는 그대로 던진다.
  private mutating func extractNextCaptureGroupBatch() async throws(IndexingStop) {
    if Task.isCancelled {
      throw .cancelled
    }
    // 방어용이다(기프티콘 소급과 같다). 보관함에 없는 이미지의 행을 읽지 않게 맞춘다.
    self.pendingCaptureGroupIDs.formIntersection(self.assets.keys)
    let batchIDs = Array(Self.newestFirst(self.pendingCaptureGroupIDs, in: self.assets).prefix(self.batchSize))
    guard !batchIDs.isEmpty else { return }
    do throws(IndexingStop) {
      let stored = try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.images(ids: Set(batchIDs))
      }
      var groups: [ImageAsset.ID: CaptureGroups] = [:]
      for image in stored where !image.categories.isDisjoint(with: CaptureGroupExtractor.categories) {
        guard let lines = image.textLines, self.assets[image.id] != nil else { continue }
        groups[image.id] = CaptureGroupExtractor.extract(from: lines, categories: image.categories)
      }
      if !groups.isEmpty {
        let batch = groups
        try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.saveCaptureGroups(batch) }
      }
      self.pendingCaptureGroupIDs.subtract(batchIDs)
    } catch {
      // 기프티콘·영수증 소급과 같은 이유로 이번 실행에서는 캡처 묶음 소급만 멈추고 분류·2단계·다른 소급은 이어 간다.
      // 다음 실행이나 전체 다시 비교가 대상을 다시 채운다. 저장소 실패가 아닌 오류(취소 등)는 삼키지 않는다.
      guard error == .storeFailed else { throw error }
      self.pendingCaptureGroupIDs = []
    }
  }
}
