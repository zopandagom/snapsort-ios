import ClassifierInterface
import Core
import Foundation
import IndexingInterface
import PhotoStoreInterface

/// 언어 모델 보강 (docs/ARCHITECTURE.md §4 인덱싱).
/// 2단계가 부르는 분류 보강·추출 보강과, 보강을 마치지 않은 저장 기프티콘을 OCR 없이 저장된 줄로 다시 보강하는 소급 보강.
/// 모델 답은 Core(`ModelCategoryPolicy`, `GifticonExtractor.filling`)가 원문으로 확인한 것만 쓴다.
/// 모델을 쓸 수 없거나 모델이 실패해도 인덱싱은 멈추지 않고 규칙 결과로 이어 간다. 취소만 던진다.
/// 읽은 텍스트와 모델 답은 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
extension IndexingRun {
  /// 모델이 이 수만큼 잇달아 실패하면 이번 실행(다음 전체 다시 비교까지)에서는 모델을 부르지 않는다. 임시 값이다.
  static let maximumConsecutiveModelFailures = 3

  /// 지금 모델을 부를지. 쓸 수 있음은 기기 설정·모델 다운로드로 실행 도중 바뀌므로 부를 때마다 묻는다.
  var canUseModel: Bool {
    !self.isModelSuspended && self.classifier.isModelAvailable()
  }

  // MARK: - 2단계 보강

  /// 규칙 분류가 기타뿐인 이미지의 카테고리를 모델 제안 중 원문 근거가 있는 정보형으로 바꾼다.
  /// 모델을 쓰지 못했거나 근거 있는 제안이 없으면 nil 이다(규칙 결과를 쓴다).
  mutating func modelCategories(for lines: [RecognizedTextLine]) async throws(IndexingStop) -> Set<ImageCategory>? {
    guard self.canUseModel else { return nil }
    let classifier = self.classifier
    let result = try await self.askModel { () async throws(ClassifierError) in try await classifier.classify(lines) }
    guard case let .answered(proposed) = result else { return nil }
    let accepted = ModelCategoryPolicy.accepted(proposed, textLines: lines)
    return accepted.isEmpty ? nil : accepted
  }

  /// 2단계 기프티콘 추출: 규칙으로 추출하고, 채울 필드가 있고 모델을 쓸 수 있으면 확인된 모델 값으로 채운다.
  /// 저장할 추출 값과 보강 상태를 돌려준다. 입력 때문에 실패한 이미지는 실패 수 1 인 보강 대기로, 모델을 못 쓰거나 시스템이 거부한 이미지는
  /// 보강 대기로 둔다. 보강 값은 `GifticonInfo.modelFilledFields` 로 출처와 함께 저장한다(`filling` 이 채운 필드를 표시한다).
  mutating func extractGifticon(
    from lines: [RecognizedTextLine],
    asset: ImageAsset
  ) async throws(IndexingStop) -> (GifticonInfo, GifticonModelFill) {
    let rules = GifticonExtractor.extract(from: lines, referenceDate: asset.creationDate, calendar: self.calendar)
    guard GifticonExtractor.needsModelFill(rules, textLines: lines) else { return (rules, .done) }
    guard self.canUseModel else { return (rules, .pending(failures: 0)) }
    switch try await self.askModelToExtract(lines) {
    case let .answered(answer):
      return (self.filling(rules, with: answer, from: lines, asset: asset), .done)
    case .failed:
      return (rules, .pending(failures: 1))
    case .rejected, .unavailable:
      return (rules, .pending(failures: 0))
    }
  }

  // MARK: - 소급 보강

  /// 소급 보강 한 배치를 한다. 소급 추출처럼 배치마다 진행률을 보내지 않고, 대상이 비면(다 마쳤거나 저장소 실패로 멈춤)
  /// 같은 값의 진행률을 한 번 보낸다(받는 쪽이 보강한 추출 값으로 만료 알림을 다시 맞출 기회. 카테고리·개수는 바뀌지 않는다).
  /// `loop` 가 대상이 있을 때만 부르므로 비는 순간 한 번이다. 취소로 던질 때는 보내지 않는다.
  mutating func fillGifticonBatch(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    try await self.fillNextGifticonBatch()
    if self.pendingModelFillIDs.isEmpty {
      report(self.progress)
    }
  }

  /// 대상 중 최신 `textBatchSize` 장을 저장된 줄로 규칙 추출부터 다시 계산하고, 채울 필드가 있으면 모델로 보강해 결과를 저장한다
  /// (보강 값은 `modelFilledFields` 로 출처와 함께 저장한다). 출처 없이 마친 옛 행(`.sourcesUnknown`)은 모델 없이 출처만 정해 마친다.
  /// 모델 없이 끝나는 행(채울 필드가 없음)은 규칙 값으로 마치고, 모델을 쓰지 못하면 옛 보강 버전 행(`.stale`)만 규칙 값으로 되돌린다
  /// (보강 대기 행은 이미 규칙 값이라 쓸 것이 없다). 시스템이 거부한 행도 같게 하고(행 실패로 세지 않는다) 배치 나머지는 계속 묻는다.
  /// 응답 도중 모델을 쓸 수 없게 되면 이 배치의 나머지도 쓸 수 없다고 본다.
  /// 고른 배치는 결과가 없어도 모두 대상에서 빼서 같은 실행에서 다시 시도하지 않는다. 건너뛴 행은 다음 실행·전체 다시 비교가 다시 읽는다.
  /// 저장소를 읽거나 쓰지 못하면 던지지 않고 이번 실행의 소급 보강만 멈춘다. 취소는 배치를 저장하지 않고 던진다.
  private mutating func fillNextGifticonBatch() async throws(IndexingStop) {
    if Task.isCancelled {
      throw .cancelled
    }
    // 방어용이다. 대상은 보관함에 있는 이미지에서 고르고 삭제 변경은 `apply` 가 먼저 뺀다.
    self.pendingModelFillIDs.formIntersection(self.assets.keys)
    let batchIDs = Array(Self.newestFirst(self.pendingModelFillIDs, in: self.assets).prefix(self.textBatchSize))
    guard !batchIDs.isEmpty else { return }
    do throws(IndexingStop) {
      let stored = try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.images(ids: Set(batchIDs))
      }
      let storedByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      var results: [ImageAsset.ID: GifticonModelFillResult] = [:]
      var isModelUnavailable = false
      for id in batchIDs {
        if Task.isCancelled {
          throw .cancelled
        }
        guard let image = storedByID[id], let asset = self.assets[id] else { continue }
        results[id] = try await self.modelFillResult(for: image, asset: asset, isModelUnavailable: &isModelUnavailable)
      }
      // 변경은 배치 사이에만 반영하므로 방어용이다. 지워진 이미지의 행에 쓰지 않는다.
      let assets = self.assets
      let batch = results.filter { assets[$0.key] != nil }
      if !batch.isEmpty {
        try await self.store { () async throws(PhotoStoreError) in
          try await self.photoStore.saveGifticonModelFills(batch)
        }
      }
      self.pendingModelFillIDs.subtract(batchIDs)
    } catch {
      // 소급 추출과 같은 이유로 이번 실행에서는 소급 보강만 멈추고 분류·2단계는 이어 간다(IndexingRun+Gifticon.swift).
      // 같은 실패를 되풀이하지 않게 대상을 모두 비우고, 다음 실행이나 전체 다시 비교가 다시 채운다. 취소는 삼키지 않는다.
      guard error == .storeFailed else { throw error }
      self.pendingModelFillIDs = []
    }
  }

  /// 소급 보강 한 장의 결과. 보강 대기가 아닌 행이거나, 모델을 쓰지 못했거나 시스템이 거부한 보강 대기 행(이미 규칙 값이라 쓸 것이 없다)이면
  /// nil 이다. 시스템 거부는 이 행만 그렇게 두고 배치 나머지는 계속 묻는다.
  /// 출처 없이 마친 옛 행(`.sourcesUnknown`)은 모델을 부르지 않고, 다시 계산한 규칙 값과 저장된 값을 비교해 출처만 정한다
  /// (`GifticonExtractor.modelFilledFields(stored:rules:)`). 그래서 모델을 쓸 수 있는지·연속 실패 차단과 관계없이 같은 결과다.
  /// 응답 도중 모델을 쓸 수 없게 되면 `isModelUnavailable` 을 켜 이 배치의 나머지에서 모델을 부르지 않는다.
  private mutating func modelFillResult(
    for image: IndexedImage,
    asset: ImageAsset,
    isModelUnavailable: inout Bool
  ) async throws(IndexingStop) -> GifticonModelFillResult? {
    guard image.categories.contains(.gifticon), let lines = image.textLines, image.gifticon != nil,
          image.gifticonModelFill != .done
    else { return nil }
    let rules = GifticonExtractor.extract(from: lines, referenceDate: asset.creationDate, calendar: self.calendar)
    // `.stale` 비교보다 앞에 둔다(보강 상태를 `==` 로만 비교해 새 상태를 컴파일러가 잡지 않는다).
    if image.gifticonModelFill == .sourcesUnknown, let stored = image.gifticon {
      return .resolvedSources(GifticonInfo(
        expiryDate: stored.expiryDate,
        redemptionPlace: stored.redemptionPlace,
        modelFilledFields: GifticonExtractor.modelFilledFields(stored: stored, rules: rules)
      ))
    }
    guard GifticonExtractor.needsModelFill(rules, textLines: lines) else { return .filled(rules) }
    if !isModelUnavailable, self.canUseModel {
      switch try await self.askModelToExtract(lines) {
      case let .answered(answer):
        return .filled(self.filling(rules, with: answer, from: lines, asset: asset))
      case .failed:
        return .failed(rules: rules)
      case .rejected:
        break
      case .unavailable:
        isModelUnavailable = true
      }
    }
    // 옛 보강 버전 행은 모델 없이도(쓸 수 없음·시스템 거부) 옛 모델 값을 규칙 값으로 되돌린다.
    return image.gifticonModelFill == .stale ? .deferred(rules: rules) : nil
  }

  // MARK: - 모델 호출

  private func filling(
    _ rules: GifticonInfo,
    with answer: GifticonModelAnswer,
    from lines: [RecognizedTextLine],
    asset: ImageAsset
  ) -> GifticonInfo {
    GifticonExtractor.filling(
      rules,
      with: answer,
      from: lines,
      referenceDate: asset.creationDate,
      calendar: self.calendar
    )
  }

  private mutating func askModelToExtract(
    _ lines: [RecognizedTextLine]
  ) async throws(IndexingStop) -> ModelResult<GifticonModelAnswer> {
    let classifier = self.classifier
    return try await self.askModel { () async throws(ClassifierError) in
      try await classifier.extractGifticon(from: lines)
    }
  }

  /// 모델을 한 번 부르고 연속 실패를 센다. 취소면 인덱싱을 멈추고, 쓸 수 없음·시스템 거부는 행 실패로 세지 않는다
  /// (시스템 거부는 연속 실패에는 센다).
  /// 연속 실패가 한도에 닿으면 이번 실행에서 모델 호출만 멈춘다(대상은 그대로 두고 규칙 결과로 이어 간다).
  private mutating func askModel<Output>(
    _ request: () async throws(ClassifierError) -> Output
  ) async throws(IndexingStop) -> ModelResult<Output> {
    do throws(ClassifierError) {
      let output = try await request()
      self.consecutiveModelFailures = 0
      return .answered(output)
    } catch {
      switch error {
      case .cancelled:
        throw .cancelled
      case .unavailable:
        return .unavailable
      case .failed:
        self.recordConsecutiveModelFailure()
        return .failed
      case .rejected:
        self.recordConsecutiveModelFailure()
        return .rejected
      }
    }
  }

  /// 연속 실패를 하나 세고, 한도에 닿으면 이번 실행에서 모델 호출을 멈춘다.
  private mutating func recordConsecutiveModelFailure() {
    self.consecutiveModelFailures += 1
    if self.consecutiveModelFailures >= Self.maximumConsecutiveModelFailures {
      self.isModelSuspended = true
    }
  }
}

/// 모델 호출 한 번의 결과. 취소는 결과가 아니라 던진다.
enum ModelResult<Output> {
  case answered(Output)
  /// 이 입력에서 실패했다. 행 실패와 연속 실패로 센다.
  case failed
  /// 입력과 관계없이 시스템이 받지 않았다. 행 실패로 세지 않고 연속 실패에는 센다.
  case rejected
  /// 모델을 지금 쓸 수 없다.
  case unavailable
}
