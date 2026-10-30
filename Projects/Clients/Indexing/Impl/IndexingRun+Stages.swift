import Core
import Foundation
import ImageAnalysisInterface
import IndexingInterface
import PhotoLibraryInterface
import PhotoStoreInterface
import Synchronization

/// 분석 두 단계 (docs/ARCHITECTURE.md §4 인덱싱).
/// 1단계(`classify(_:)`)는 새 이미지를 모두 분류해 저장하고(벡터 대상 사진은 같은 썸네일로 특징 벡터도 만들어 같은 저장에 넣는다), 2단계(`recognize(_:asset:)`)는 OCR 대기
/// 이미지의 글자를 나중에 읽어
/// 규칙 분류하고, 기프티콘이면 만료일·교환처를, 영수증이면 가게·금액을, 쇼핑·대화·지도면 쇼핑몰·브랜드·대화 앱·지역을 추출해 함께 저장한다. 모델을 쓸 수 있으면 2단계가 언어 모델로 보강한다:
/// 규칙 분류가 기타뿐인 이미지에 근거 있는 정보형 카테고리를 더하고, 기프티콘 추출 값의 빈 필드를 확인된 값으로 채운다(IndexingRun+ModelFill.swift).
/// Debug 기록 도구의 `SampleRecording.measure`(SampleRecorderFeature)는 한 장에서 두 단계를 이어 단계별 시간을 잰다.
/// 한쪽 단계 내용을 바꾸면 다른 쪽도 맞춘다(기록 도구도 1단계처럼 확인 대상의 바코드와 대상 사진의 특징 벡터 시간을 잰다). 규칙 분류와 기프티콘·영수증·캡처 묶음 규칙 추출은 순수 계산이라 기록 도구가
/// 재지 않고,
/// 언어 모델 보강은 기록 도구가 하지 않아 재지 않는다(기록 도구는 Classifier 를 주입받지 않는다).
extension IndexingRun {
  // MARK: - 1단계: 분류

  /// 이미지를 차례로 분류하고 `batchSize` 장마다 저장하고 진행률을 보낸다. 1단계 도중에는 보관함 변경을 보지 않는다.
  mutating func classifyAll(
    _ targets: [ImageAsset],
    report: (IndexingProgress) -> Void
  ) async throws(IndexingStop) {
    guard !targets.isEmpty else { return }
    var pending: [IndexedImage] = []
    var processedSinceReport = 0
    var foundGone = false
    for asset in targets {
      if Task.isCancelled {
        throw .cancelled
      }
      switch try await self.classify(asset) {
      case let .indexed(image):
        pending.append(image)
      case .unavailable, .deferred:
        self.skippedIDs.insert(asset.id)
      case .gone:
        // 보관함에서 지워졌다. 삭제 변경도 오지만 그 전에 전체 수와 여행에서 뺀다.
        self.assets[asset.id] = nil
        foundGone = true
      }
      processedSinceReport += 1
      if self.shouldStopForVisionFailures {
        // 분석한 결과는 저장한 뒤 멈춘다.
        try await self.saveClassified(&pending)
        report(self.progress)
        throw .visionStopped
      }
      if processedSinceReport >= self.batchSize {
        try await self.saveClassified(&pending)
        processedSinceReport = 0
        report(self.progress)
        try self.yieldIfNeeded()
      }
    }
    try await self.saveClassified(&pending)
    if foundGone {
      try await self.replaceTripsIfChanged()
    }
    report(self.progress)
  }

  /// 1단계: ① 메타데이터 → ② 썸네일 이미지 분류 → OCR 대상 판정(위치 없고 라벨로는 대상이 아니면 같은 썸네일로 바코드 확인,
  /// `phaseOneHasBarcode`) → 벡터 대상이면 같은 썸네일로 특징 벡터.
  /// OCR 대상은 대기(`.pending`)로, 카테고리는 라벨만으로 정한 것(`pendingCategories`)으로 저장한다. 바코드는 카테고리에 쓰지 않는다.
  /// 벡터를 만들지 못하면 벡터 없이 분류를 저장한다(`phaseOneFeaturePrint`, 다음 실행·전체 다시 비교가 대기로 고른다).
  mutating func classify(_ asset: ImageAsset) async throws(IndexingStop) -> Outcome {
    let thumbnail: AnalysisImage
    let labels: [ImageLabel]
    do throws(AnalysisFailure) {
      thumbnail = try await self.loadImage(asset.id, size: .thumbnail)
      let imageAnalysis = self.imageAnalysis
      labels = try await self.analysis { () async throws(ImageAnalysisError) in
        try await imageAnalysis.classify(thumbnail, minimumConfidence: ClassificationRules.minimumLabelConfidence)
      }
    } catch let failure {
      return try failure.outcome()
    }
    // BG 모드의 바코드 확인 실패는 바코드 없음으로 굳히지 않고 미룬다.
    guard let hasBarcode = try await self.phaseOneHasBarcode(asset: asset, labels: labels, thumbnail: thumbnail) else {
      return .deferred
    }
    guard TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: labels, hasBarcode: hasBarcode) else {
      let categories = RuleClassifier.classify(asset: asset, labels: labels, textLines: [])
      let featurePrint = try await self.phaseOneFeaturePrint(asset: asset, thumbnail: thumbnail)
      return .indexed(IndexedImage(
        asset: asset,
        labels: labels,
        textRecognition: .notNeeded,
        categories: categories,
        featurePrint: featurePrint
      ))
    }
    return .indexed(IndexedImage(
      asset: asset,
      labels: labels,
      textRecognition: .pending,
      categories: Self.pendingCategories(asset: asset, labels: labels)
    ))
  }

  /// OCR 대기 이미지의 카테고리: 라벨만으로 정한 규칙 분류에서 `.other` 를 뺀 것.
  /// 규칙 분류는 같은 규칙 안에서 OCR 전(줄 없음)의 결과에 줄을 더하면 카테고리가 늘기만 하므로(Core `RuleClassifier`), 2단계는 카테고리를 더하기만 한다.
  /// 2단계는 저장된 라벨과 읽은 줄로 다시 계산하므로, 1단계와 2단계 사이에 앱 업데이트로 규칙이 바뀌면 빠질 수 있다(docs/ARCHITECTURE.md §4 저장소).
  /// `.other` 를 빼 두어 "기타" 수가 1단계에 부풀었다가 줄지 않게 하고, 글자를 읽어도 규칙도 모델 보강도 근거 있는 카테고리를 찾지 못한 이미지만
  /// 2단계 뒤 `.other` 가 된다.
  static func pendingCategories(asset: ImageAsset, labels: [ImageLabel]) -> Set<ImageCategory> {
    RuleClassifier.classify(asset: asset, labels: labels, textLines: []).subtracting([.other])
  }

  private mutating func saveClassified(_ pending: inout [IndexedImage]) async throws(IndexingStop) {
    guard !pending.isEmpty else { return }
    let images = pending
    try await self.store(write: true) { () async throws(PhotoStoreError) in try await self.photoStore.save(images) }
    self.environment.record(.classified(images.count))
    self.indexedIDs.formUnion(images.map(\.id))
    self.pendingTextIDs.formUnion(images.filter { $0.textRecognition == .pending }.map(\.id))
    pending = []
  }

  // MARK: - 2단계: 글자 읽기

  /// OCR 대기 이미지 중 최신 `textBatchSize` 장을 읽어 바꿔 저장하고 진행률을 보낸다.
  /// 원본을 읽거나 OCR 하지 못하면 저장 결과를 1단계 결과(대기)로 두고 이번 실행에서 미룬다.
  /// 보관함에 없다고 나오면(`notFound`) 저장 결과는 지우지 않고(삭제는 보관함 변경이 한다) 전체 수·여행에서만 뺀다.
  /// 그 이미지가 삭제 없이 다시 추가되면 `apply` 가 대기로 되돌린다(`goneTextIDs`).
  /// 저장 결과가 없는 대기 이미지는 1단계 미룸으로 옮긴다.
  mutating func recognizeBatch(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    // 대기는 늘 보관함 안이지만, 어긋나도 할 일 없이 도는 일이 없게 맞춘다.
    self.pendingTextIDs.formIntersection(self.assets.keys)
    let batchIDs = Array(Self.newestFirst(self.pendingTextIDs, in: self.assets).prefix(self.textBatchSize))
    guard !batchIDs.isEmpty else { return }
    let stored = try await self.store { () async throws(PhotoStoreError) in
      try await self.photoStore.images(ids: Set(batchIDs))
    }
    let storedByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var recognized: [IndexedImage] = []
    var foundGone = false
    for id in batchIDs {
      if Task.isCancelled {
        throw .cancelled
      }
      if let result = try await self.recognizeOne(id, stored: storedByID[id], foundGone: &foundGone) {
        recognized.append(result)
      }
      if self.shouldStopForVisionFailures {
        // 읽은 결과는 저장한 뒤 멈춘다. 남은 장은 대기로 남는다.
        break
      }
    }
    // 삭제는 배치 사이에만 반영하므로 방어용이다. 지워진 이미지의 행을 다시 만들지 않는다.
    let images = recognized.filter { self.assets[$0.id] != nil }
    if !images.isEmpty {
      try await self.store(write: true) { () async throws(PhotoStoreError) in try await self.photoStore.save(images) }
      self.environment.record(.recognized(images.count))
      self.pendingTextIDs.subtract(images.map(\.id))
      self.recognizedTextCount += images.count
    }
    if foundGone {
      try await self.replaceTripsIfChanged()
    }
    report(self.progress)
    if self.shouldStopForVisionFailures {
      throw .visionStopped
    }
  }

  /// 2단계 배치의 한 장을 읽는다. 읽은 결과를 돌려주고, 읽지 못했으면 대기에서 빼 알맞은 곳으로 옮긴다.
  /// 보관함에 없다고 나오면 `foundGone` 을 켠다.
  private mutating func recognizeOne(
    _ id: ImageAsset.ID,
    stored: IndexedImage?,
    foundGone: inout Bool
  ) async throws(IndexingStop) -> IndexedImage? {
    guard let asset = self.assets[id] else {
      self.pendingTextIDs.remove(id)
      return nil
    }
    guard let image = stored else {
      // 저장 결과가 없으면 읽을 라벨이 없다. 저장 수에서도 빼고 1단계 미룸으로 옮겨, 진행률이 행 없는 이미지를 저장된 것으로 세지 않고
      // 전체 다시 비교나 다음 실행의 1단계가 다시 분류하게 한다. 저장 수에서만 빼면 할 일 없이 1단계에 머문다.
      self.pendingTextIDs.remove(id)
      self.indexedIDs.remove(id)
      self.skippedIDs.insert(id)
      return nil
    }
    switch try await self.recognize(image, asset: asset) {
    case let .indexed(result):
      return result
    case .unavailable, .deferred:
      self.pendingTextIDs.remove(id)
      self.textSkippedIDs.insert(id)
    case .gone:
      // 저장 결과는 지우지 않는다(삭제는 보관함 변경이 한다). 삭제 없이 다시 추가되면 대기로 되돌린다.
      self.pendingTextIDs.remove(id)
      self.goneTextIDs.insert(id)
      self.assets[id] = nil
      foundGone = true
    }
    return nil
  }

  /// 2단계: 가장 큰 버전으로 OCR → 저장된 라벨과 지금 보관함의 메타데이터, 읽은 줄로 규칙 분류 → 기타뿐이면 모델 분류 보강
  /// → 영수증이면 가게·금액 추출(모델이 더한 영수증 카테고리도) → 쇼핑·대화·지도면 묶음 값 추출 → 기프티콘이면 추출과 모델 추출 보강. 기프티콘 추출의 기준일은 카테고리와 같이 지금 보관함의
  /// 생성일이고, 날짜는 인덱서의 달력으로 나눈다.
  /// 모델을 부르기 전이나 응답 도중·뒤에 Task 가 취소되면 던져 이 배치를 버린다. 모델을 쓸 수 없거나 실패하면 규칙 결과로 저장한다.
  mutating func recognize(_ stored: IndexedImage, asset: ImageAsset) async throws(IndexingStop) -> Outcome {
    let lines: [RecognizedTextLine]
    do throws(AnalysisFailure) {
      let image = try await self.loadImage(asset.id, size: .largestAvailable)
      let imageAnalysis = self.imageAnalysis
      lines = try await self.analysis { () async throws(ImageAnalysisError) in
        try await imageAnalysis.recognizeText(image)
      }
    } catch let failure {
      return try failure.outcome()
    }
    var categories = RuleClassifier.classify(asset: asset, labels: stored.labels, textLines: lines)
    if categories == [.other], !lines.isEmpty {
      switch try await self.modelCategories(for: lines) {
      case let .accepted(accepted):
        categories = accepted
      case .rules:
        break
      case .deferred:
        return .deferred
      }
    }
    let receipt = categories.contains(.receipt) ? ReceiptExtractor.extract(from: lines) : nil
    // 모델이 더한 쇼핑·대화·지도 카테고리도 추출한다. 세 카테고리가 아니면 값이 없다(nil).
    let captureGroups = categories.isDisjoint(with: CaptureGroupExtractor.categories)
      ? nil
      : CaptureGroupExtractor.extract(from: lines, categories: categories)
    guard categories.contains(.gifticon) else {
      return .indexed(IndexedImage(
        asset: asset,
        labels: stored.labels,
        textRecognition: .recognized(lines),
        categories: categories,
        receipt: receipt,
        captureGroups: captureGroups
      ))
    }
    let (gifticon, fill) = try await self.extractGifticon(from: lines, asset: asset)
    return .indexed(IndexedImage(
      asset: asset,
      labels: stored.labels,
      textRecognition: .recognized(lines),
      categories: categories,
      gifticon: gifticon,
      gifticonModelFill: fill,
      receipt: receipt,
      captureGroups: captureGroups
    ))
  }

  /// 최신순. 생성일이 없으면 맨 뒤, 같으면 식별자 순(저장소의 카테고리 목록 순서와 같은 규칙).
  static func newestFirst(_ ids: Set<ImageAsset.ID>, in assets: [ImageAsset.ID: ImageAsset]) -> [ImageAsset.ID] {
    ids.sorted { lhs, rhs in
      switch (assets[lhs]?.creationDate, assets[rhs]?.creationDate) {
      case let (left?, right?) where left != right:
        left > right
      case (.some, nil):
        true
      case (nil, .some):
        false
      default:
        lhs < rhs
      }
    }
  }

  // MARK: - 오류 변환

  func loadImage(_ id: ImageAsset.ID, size: ImageSize) async throws(AnalysisFailure) -> AnalysisImage {
    do throws(ImageLoadError) {
      return try await self.photoLibrary.loadImage(id: id, size: size)
    } catch {
      switch error {
      case .cancelled: throw .cancelled
      case .notFound: throw .gone
      case .notAvailableLocally, .failed: throw .unavailable
      }
    }
  }

  /// 분류·OCR Vision 요청. 성공·실패를 BG 모드의 Vision 연속 실패로 센다(IndexingRun+Background.swift).
  private mutating func analysis<Output>(
    _ operation: () async throws(ImageAnalysisError) -> Output
  ) async throws(AnalysisFailure) -> Output {
    do throws(ImageAnalysisError) {
      let output = try await operation()
      self.recordVisionResult(succeeded: true)
      return output
    } catch {
      switch error {
      case .cancelled:
        throw .cancelled
      case .failed:
        self.recordVisionResult(succeeded: false)
        throw .unavailable
      }
    }
  }
}

/// 이미지 한 장의 분석 결과(1·2단계 공통).
enum Outcome {
  case indexed(IndexedImage)
  /// 읽거나 분석하지 못했다. 1단계는 저장하지 않고, 2단계는 1단계 결과(대기)로 둔 채 미룬다.
  case unavailable
  /// 보관함에 없다.
  case gone
  /// BG 모드라 결과로 굳히지 않고 미룬다(바코드 확인 실패·분류 보강 거부). 1단계는 저장하지 않고, 2단계는 대기로 둔다.
  case deferred
}

/// 인덱싱을 멈추는 이유.
enum IndexingStop: Error {
  /// Task 취소 또는 닫힌 저장소 문(실행을 멈췄다).
  case cancelled
  case storeFailed
  /// 사진을 읽을 권한이 없다.
  case notReadable
  /// BG 모드에서 양보했다(발열).
  case yielded
  /// BG 모드에서 Vision 이 잇달아 실패했다.
  case visionStopped
  /// BG 모드에서 사진 조회가 비었는데 저장된 결과가 있다(지우지 않고 앞 실행에 넘긴다).
  case libraryEmpty
}

/// 이미지 한 장을 분석하지 못한 이유.
enum AnalysisFailure: Error {
  case cancelled
  case unavailable
  case gone

  /// 취소면 인덱싱을 멈추고, 그 밖에는 이 이미지만 건너뛴다.
  func outcome() throws(IndexingStop) -> Outcome {
    switch self {
    case .cancelled: throw .cancelled
    case .unavailable: .unavailable
    case .gone: .gone
    }
  }
}

/// 2단계 도중 받은 보관함 변경을 본 루프가 배치 경계에서 꺼낼 때까지 쌓아 둔다.
/// 변경 받기 자식 Task 와 본 루프가 함께 쓰므로 Mutex 로 보호한다. `run()` 하나의 값이라 실행 사이에 공유하지 않는다.
final class ChangeInbox: Sendable {
  private struct State {
    var changes: [ImageChange] = []
    var isFinished = false
  }

  private let state = Mutex(State())

  func append(_ change: ImageChange) {
    self.state.withLock { $0.changes.append(change) }
  }

  /// 변경 스트림이 끝났다. 남은 변경은 그대로 꺼낼 수 있다.
  func finish() {
    self.state.withLock { $0.isFinished = true }
  }

  /// 쌓인 변경을 받은 순서대로 모두 꺼내고, 그 시점에 스트림이 끝났는지 함께 준다.
  /// 한 번의 잠금으로 읽어, 끝났다고 본 뒤에 남은 변경을 놓치지 않는다.
  func takeAll() -> (changes: [ImageChange], isFinished: Bool) {
    self.state.withLock { state in
      let changes = state.changes
      state.changes = []
      return (changes, state.isFinished)
    }
  }
}
