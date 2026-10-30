import Core
import Foundation
import IndexingInterface
import PhotoStoreInterface

/// 기프티콘 소급 추출 (docs/ARCHITECTURE.md §4 인덱싱).
/// 2단계보다 먼저 저장된 기프티콘(저장소 경량 이전 뒤)이나 규칙 버전을 올리기 전에 추출한 기프티콘을, OCR 없이 저장된 줄로 다시 추출한다.
extension IndexingRun {
  /// 기프티콘 소급 추출 한 배치를 한다. 배치마다 진행률을 보내지 않고, 대상이 비면(다 마쳤거나 실패로 멈춤) 같은 값의 진행률을 한 번 보낸다
  /// (받는 쪽이 추출 값으로 다시 계산할 기회. 카테고리·개수는 바뀌지 않는다). `loop` 가 대상이 있을 때만 부르므로 비는 순간 한 번이다.
  /// 취소로 던질 때는 보내지 않는다.
  mutating func extractGifticonBatch(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    try await self.extractNextGifticonBatch()
    if self.pendingGifticonIDs.isEmpty {
      report(self.progress)
    }
  }

  /// 기프티콘 소급 대상 중 최신 `batchSize` 장의 저장된 줄로 추출해 추출 값만 저장한다.
  /// 고른 배치는 저장할 것이 없어도 모두 대상에서 빼서, 저장 행이 없거나 조건이 맞지 않는 이미지로 같은 실행에서 다시 돌지 않는다.
  /// 저장소는 기프티콘·읽음·추출 안 함 행만 바꾸므로, 그 사이 지워졌거나 다시 대기가 된 행에는 쓰지 않는다.
  /// 저장한 값에 모델로 채울 필드가 있으면 소급 보강 대상에 더해 같은 실행에서 보강까지 한다(저장소가 보강 상태를 되돌린다).
  /// 저장소를 읽거나 쓰지 못하면 던지지 않고 이번 실행의 기프티콘 소급만 멈춘다(`stopGifticonBackfill()`). 취소는 그대로 던진다.
  private mutating func extractNextGifticonBatch() async throws(IndexingStop) {
    if Task.isCancelled {
      throw .cancelled
    }
    // 방어용이다. 지금 경로에서는 소급 대상이 늘 `assets` 안에 있다(대상은 저장소·보관함에 모두 있는 이미지에서 고르고,
    // 삭제 변경은 `apply` 가 먼저 뺀다). 어긋나도 보관함에 없는 이미지의 행을 읽지 않게 맞춘다.
    self.pendingGifticonIDs.formIntersection(self.assets.keys)
    let batchIDs = Array(Self.newestFirst(self.pendingGifticonIDs, in: self.assets).prefix(self.batchSize))
    guard !batchIDs.isEmpty else { return }
    do throws(IndexingStop) {
      let stored = try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.images(ids: Set(batchIDs))
      }
      var gifticons: [ImageAsset.ID: GifticonInfo] = [:]
      var needsModelFill: Set<ImageAsset.ID> = []
      for image in stored where image.categories.contains(.gifticon) {
        guard let lines = image.textLines, let asset = self.assets[image.id] else { continue }
        let gifticon = GifticonExtractor.extract(
          from: lines,
          referenceDate: asset.creationDate,
          calendar: self.calendar
        )
        gifticons[image.id] = gifticon
        if GifticonExtractor.needsModelFill(gifticon, textLines: lines) {
          needsModelFill.insert(image.id)
        }
      }
      if !gifticons.isEmpty {
        let batch = gifticons
        try await self
          .store(write: true) { () async throws(PhotoStoreError) in try await self.photoStore.saveGifticons(batch) }
      }
      self.pendingGifticonIDs.subtract(batchIDs)
      // 저장에 성공한 뒤에만 더한다. 저장소가 쓰지 않은 행이 섞여도 소급 보강 저장이 조건을 다시 보므로 무해하다.
      // 모델을 쓸 수 없으면 소급 보강이 쓰지 않고 뺀다.
      self.pendingModelFillIDs.formUnion(needsModelFill)
    } catch {
      // 기프티콘 소급은 카테고리·개수를 바꾸지 않으므로, 저장소 실패로 멈추면 다 분석한 뒤 "새 사진을 분류하지 못했다"는 틀린 안내가 나온다.
      // 그래서 이번 실행에서는 기프티콘 소급만 멈추고 분류·2단계는 이어 간다. 다음 실행이나 전체 다시 비교가 대상을 다시 채운다.
      // 저장소가 정말 고장 났으면 다른 단계의 저장소 호출이 멈춘다. 저장소 실패가 아닌 오류(취소 등)는 삼키지 않는다.
      guard error == .storeFailed else { throw error }
      self.stopGifticonBackfill()
    }
  }

  /// 이번 실행에서 기프티콘 소급 추출을 멈춘다. 같은 실행에서 같은 실패를 되풀이하지 않게 대상을 모두 비운다.
  private mutating func stopGifticonBackfill() {
    self.pendingGifticonIDs = []
  }
}
