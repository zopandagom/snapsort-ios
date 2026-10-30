import Core
import Foundation
import ImageAnalysisInterface
import IndexingInterface
import PhotoStoreInterface

/// 비슷한 사진 비교용 특징 벡터 (docs/ARCHITECTURE.md §4 인덱싱·정리 도우미).
/// 1단계가 분류와 같은 썸네일로 만들고(`phaseOneFeaturePrint`), 벡터가 생기기 전에 저장된 사진·버전이 바뀐 사진·지난 실패는
/// 썸네일을 다시 읽어 소급 계산한다(`computeFeaturePrintBatch`). 벡터를 쓸 수 없거나 실패해도 인덱싱은 멈추지 않는다. 취소만 던진다.
/// BG 모드에서도 같게 요청하고, 이미지 분석의 뒤 시한 차단(`isFeaturePrintAvailable`)을 부를 때마다 따른다.
/// 벡터와 식별자는 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
extension IndexingRun {
  /// 벡터 요청이 이 수만큼 잇달아 실패하면 이번 실행(다음 전체 다시 비교까지)에서는 부르지 않는다. 임시 값이다.
  static let maximumConsecutiveFeaturePrintFailures = 3

  /// 지금 벡터를 요청할지. 요청이 시한을 넘기면 실행 도중 쓸 수 없게 되므로 부를 때마다 묻는다(그 뒤 장은 바로 건너뛴다).
  var canUseFeaturePrint: Bool {
    !self.isFeaturePrintSuspended && self.imageAnalysis.isFeaturePrintAvailable
  }

  /// 벡터 소급 대상을 조회한다. 쓸 수 없으면 조회하지 않는다(쓸 수 없는 기기에서 매 실행 비용이 없게).
  /// 대상 조회만 실패하면 이번 비교에서는 벡터 소급만 하지 않고 비교·분류는 이어 간다(빈 집합).
  func featurePrintPendingIDs() async throws(IndexingStop) -> Set<ImageAsset.ID> {
    guard self.imageAnalysis.isFeaturePrintAvailable else { return [] }
    do throws(IndexingStop) {
      return try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.featurePrintPendingIDs()
      }
    } catch {
      guard error == .storeFailed else { throw error }
      return []
    }
  }

  /// 1단계 벡터. 벡터 대상이고(OCR 대상은 부르는 쪽이 이미 걸렀다) 쓸 수 있고 썸네일이 대체 버전이 아니면 같은 썸네일로 만든다.
  /// 대체 버전(iCloud 전용 사진의 작은 버전)은 크기가 달라 같은 사진끼리도 거리가 기준을 넘으므로 쓰지 않는다.
  /// 만들지 못하면 nil(분류는 그대로 저장), 취소면 던진다.
  mutating func phaseOneFeaturePrint(
    asset: ImageAsset,
    thumbnail: AnalysisImage
  ) async throws(IndexingStop) -> ImageFeaturePrint? {
    guard ImageFeaturePrint.isTarget(asset, needsTextRecognition: false),
          !thumbnail.isLocalFallback,
          self.canUseFeaturePrint
    else {
      return nil
    }
    return try await self.requestFeaturePrint(thumbnail)
  }

  /// 벡터 소급 한 배치를 한다. 소급 추출처럼 배치마다 진행률을 보내지 않고, 대상이 비면(다 마쳤거나 저장소 실패·차단으로 멈춤)
  /// 같은 값의 진행률을 한 번 보낸다(받는 쪽이 저장소를 다시 읽어 비슷한 사진 묶음을 보일 기회. 카테고리·개수는 바뀌지 않는다).
  /// `loop` 가 대상이 있을 때만 부르므로 비는 순간 한 번이다. 취소로 던질 때는 보내지 않는다.
  mutating func computeFeaturePrintBatch(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    try await self.computeNextFeaturePrintBatch()
    if self.pendingFeaturePrintIDs.isEmpty {
      report(self.progress)
    }
  }

  /// 벡터 소급 대상 중 최신 `batchSize` 장의 썸네일을 다시 읽어 벡터를 만들고 벡터만 저장한다.
  /// 읽지 못한 장(보관함에 없음·기기에 없음)과 대체 버전은 건너뛴다(삭제는 보관함 변경이 반영한다).
  /// 고른 배치는 저장할 것이 없어도 모두 대상에서 빼서 같은 실행에서 다시 돌지 않는다. 쓸 수 없게 되거나 연속 실패로 멈추면 남은 장은 건너뛰고 대상을 비운다.
  /// 저장소를 쓰지 못하면 던지지 않고 이번 실행의 벡터 소급만 멈춘다. 취소는 그대로 던진다.
  private mutating func computeNextFeaturePrintBatch() async throws(IndexingStop) {
    if Task.isCancelled {
      throw .cancelled
    }
    guard self.canUseFeaturePrint else {
      self.pendingFeaturePrintIDs = []
      return
    }
    // 방어용이다(다른 소급과 같다). 보관함에 없는 이미지를 읽지 않게 맞춘다.
    self.pendingFeaturePrintIDs.formIntersection(self.assets.keys)
    let batchIDs = Array(Self.newestFirst(self.pendingFeaturePrintIDs, in: self.assets).prefix(self.batchSize))
    guard !batchIDs.isEmpty else { return }
    let prints = try await self.featurePrints(for: batchIDs)
    self.pendingFeaturePrintIDs.subtract(batchIDs)
    if !self.canUseFeaturePrint {
      self.pendingFeaturePrintIDs = []
    }
    // 삭제는 배치 사이에만 반영하므로 방어용이다.
    let batch = prints.filter { self.assets[$0.key] != nil }
    guard !batch.isEmpty else { return }
    do throws(IndexingStop) {
      try await self.store(write: true) { () async throws(PhotoStoreError) in
        try await self.photoStore.saveFeaturePrints(batch)
      }
    } catch {
      // 다른 소급과 같은 이유로 이번 실행에서는 벡터 소급만 멈추고 분류·2단계·소급 보강은 이어 간다.
      // 다음 실행이나 전체 다시 비교가 대상을 다시 채운다. 저장소 실패가 아닌 오류(취소 등)는 삼키지 않는다.
      guard error == .storeFailed else { throw error }
      self.pendingFeaturePrintIDs = []
    }
  }

  /// 배치의 썸네일을 차례로 다시 읽어 벡터를 만든다. 쓸 수 없게 되면 남은 장은 건너뛴다. 취소면 던진다.
  private mutating func featurePrints(
    for batchIDs: [ImageAsset.ID]
  ) async throws(IndexingStop) -> [ImageAsset.ID: ImageFeaturePrint] {
    var prints: [ImageAsset.ID: ImageFeaturePrint] = [:]
    for id in batchIDs {
      if Task.isCancelled {
        throw .cancelled
      }
      guard self.canUseFeaturePrint else { break }
      guard let thumbnail = try await self.backfillThumbnail(id) else { continue }
      if let featurePrint = try await self.requestFeaturePrint(thumbnail) {
        prints[id] = featurePrint
      }
    }
    return prints
  }

  /// 소급할 썸네일. 읽지 못했거나(보관함에 없음·기기에 없음) 대체 버전이면 nil, 취소면 던진다.
  private func backfillThumbnail(_ id: ImageAsset.ID) async throws(IndexingStop) -> AnalysisImage? {
    let thumbnail: AnalysisImage
    do throws(AnalysisFailure) {
      thumbnail = try await self.loadImage(id, size: .thumbnail)
    } catch {
      if case .cancelled = error {
        throw .cancelled
      }
      return nil
    }
    return thumbnail.isLocalFallback ? nil : thumbnail
  }

  /// 벡터를 요청한다. 성공하면 연속 실패를 0 으로, 실패하면 하나 늘리고 한도에 닿으면 이번 실행에서 멈춘다(nil). 취소면 던진다.
  private mutating func requestFeaturePrint(_ thumbnail: AnalysisImage) async throws(IndexingStop)
    -> ImageFeaturePrint?
  {
    do throws(ImageAnalysisError) {
      let featurePrint = try await self.imageAnalysis.featurePrint(thumbnail)
      self.consecutiveFeaturePrintFailures = 0
      self.environment.record(.featurePrint)
      return featurePrint
    } catch {
      switch error {
      case .cancelled:
        throw .cancelled
      case .failed:
        // BG 모드의 Vision 연속 실패(`consecutiveVisionFailures`)에는 세지 않는다(IndexingRun+Background.swift).
        self.environment.record(.featurePrintFailure)
        self.consecutiveFeaturePrintFailures += 1
        if self.consecutiveFeaturePrintFailures >= Self.maximumConsecutiveFeaturePrintFailures {
          self.isFeaturePrintSuspended = true
        }
        return nil
      }
    }
  }
}
