import Core
import Foundation
import PhotoStoreInterface

/// 소급 추출 (docs/ARCHITECTURE.md §4 인덱싱).
/// 2단계보다 먼저 저장된 기프티콘(저장소 경량 이전 뒤)이나 규칙 버전을 올리기 전에 추출한 기프티콘을, OCR 없이 저장된 줄로 다시 추출한다.
extension IndexingRun {
  /// 소급 대상 중 최신 `batchSize` 장의 저장된 줄로 추출해 추출 값만 저장한다. 진행률은 보내지 않는다(카테고리·개수가 바뀌지 않는다).
  /// 고른 배치는 저장할 것이 없어도 모두 대상에서 빼서, 저장 행이 없거나 조건이 맞지 않는 이미지로 같은 실행에서 다시 돌지 않는다.
  /// 저장소는 기프티콘·읽음·추출 안 함 행만 바꾸므로, 그 사이 지워졌거나 다시 대기가 된 행에는 쓰지 않는다.
  /// 저장소를 읽거나 쓰지 못하면 던지지 않고 이번 실행의 소급만 멈춘다(`stopGifticonBackfill()`). 취소는 그대로 던진다.
  mutating func extractGifticonBatch() async throws(IndexingStop) {
    if Task.isCancelled {
      throw .cancelled
    }
    // 삭제 변경이 대상에서 빼지만, 1단계에서 보관함에 없다고 나온 이미지는 `assets` 에서만 빠진다.
    self.pendingGifticonIDs.formIntersection(self.assets.keys)
    let batchIDs = Array(Self.newestFirst(self.pendingGifticonIDs, in: self.assets).prefix(self.batchSize))
    guard !batchIDs.isEmpty else { return }
    do throws(IndexingStop) {
      let stored = try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.images(ids: Set(batchIDs))
      }
      var gifticons: [ImageAsset.ID: GifticonInfo] = [:]
      for image in stored where image.categories.contains(.gifticon) {
        guard let lines = image.textLines, let asset = self.assets[image.id] else { continue }
        gifticons[image.id] = GifticonExtractor.extract(
          from: lines,
          referenceDate: asset.creationDate,
          calendar: self.calendar
        )
      }
      if !gifticons.isEmpty {
        let batch = gifticons
        try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.saveGifticons(batch) }
      }
      self.pendingGifticonIDs.subtract(batchIDs)
    } catch {
      // 소급은 카테고리·개수를 바꾸지 않으므로, 저장소 실패로 멈추면 다 분석한 뒤 "새 사진을 분류하지 못했다"는 틀린 안내가 나온다.
      // 그래서 이번 실행에서는 소급만 멈추고 분류·2단계는 이어 간다. 다음 실행이나 전체 다시 비교가 대상을 다시 채운다.
      // 저장소가 정말 고장 났으면 다른 단계의 저장소 호출이 멈춘다. 저장소 실패가 아닌 오류(취소 등)는 삼키지 않는다.
      guard error == .storeFailed else { throw error }
      self.stopGifticonBackfill()
    }
  }

  /// 이번 실행에서 소급 추출을 멈춘다. 같은 실행에서 같은 실패를 되풀이하지 않게 대상을 모두 비운다.
  private mutating func stopGifticonBackfill() {
    self.pendingGifticonIDs = []
  }
}
