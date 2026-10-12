import Core
import Foundation
import ImageAnalysisInterface
import IndexingInterface
import PhotoLibraryInterface
import PhotoStoreInterface

/// 다른 Client 를 조합한 구현. 이 모듈은 Apple 데이터 프레임워크를 직접 쓰지 않는다.
public struct IndexingClientImpl: IndexingClient {
  /// 한 번에 저장·삭제하는 이미지 수. 저장소는 식별자 목록 조건(`ids.contains`)으로 기존 행을 찾으므로 조건 크기를 이 수로 묶고,
  /// 중간에 멈춰도 이 수만큼만 다시 분석하게 한다. 임시 값이며 1만 장 측정 작업에서 확정한다.
  static let defaultBatchSize = 50

  private let photoLibrary: any PhotoLibraryClient
  private let imageAnalysis: any ImageAnalysisClient
  private let photoStore: any PhotoStoreClient
  private let calendar: Calendar
  private let batchSize: Int

  /// - Parameter calendar: 여행 판정에서 날짜를 나누는 달력. 앱은 기기 달력을 넘긴다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    imageAnalysis: any ImageAnalysisClient,
    photoStore: any PhotoStoreClient,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.init(
      photoLibrary: photoLibrary,
      imageAnalysis: imageAnalysis,
      photoStore: photoStore,
      calendar: calendar,
      batchSize: Self.defaultBatchSize
    )
  }

  init(
    photoLibrary: any PhotoLibraryClient,
    imageAnalysis: any ImageAnalysisClient,
    photoStore: any PhotoStoreClient,
    calendar: Calendar,
    batchSize: Int
  ) {
    self.photoLibrary = photoLibrary
    self.imageAnalysis = imageAnalysis
    self.photoStore = photoStore
    self.calendar = calendar
    self.batchSize = max(batchSize, 1)
  }

  /// 화면 응답을 막지 않도록 낮은 우선순위(`.utility`)로 메인 밖에서 분석한다.
  public func run() -> AsyncStream<IndexingProgress> {
    let (stream, continuation) = AsyncStream.makeStream(of: IndexingProgress.self, bufferingPolicy: .bufferingNewest(1))
    let task = Task(priority: .utility) { [self] in
      var indexing = IndexingRun(
        photoLibrary: self.photoLibrary,
        imageAnalysis: self.imageAnalysis,
        photoStore: self.photoStore,
        calendar: self.calendar,
        batchSize: self.batchSize
      )
      await indexing.start { continuation.yield($0) }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}

/// `run()` 한 번의 상태. 한 Task 안에서만 쓴다.
struct IndexingRun {
  let photoLibrary: any PhotoLibraryClient
  let imageAnalysis: any ImageAnalysisClient
  let photoStore: any PhotoStoreClient
  let calendar: Calendar
  let batchSize: Int

  /// 보관함 이미지. 여행 판정과 전체 수에 쓴다.
  private var assets: [ImageAsset.ID: ImageAsset] = [:]
  /// 저장소에 결과가 있는 보관함 이미지.
  private var indexedIDs: Set<ImageAsset.ID> = []
  /// 이번 실행에서 미룬 이미지. 전체 다시 비교(`.reloadAll`)나 다음 실행에서 다시 시도한다.
  private var skippedIDs: Set<ImageAsset.ID> = []
  /// 마지막으로 여행을 판정한 보관함. 같은 보관함으로 다시 판정·저장하지 않으려고 둔다.
  private var judgedAssets: [ImageAsset.ID: ImageAsset]?

  init(
    photoLibrary: any PhotoLibraryClient,
    imageAnalysis: any ImageAnalysisClient,
    photoStore: any PhotoStoreClient,
    calendar: Calendar,
    batchSize: Int
  ) {
    self.photoLibrary = photoLibrary
    self.imageAnalysis = imageAnalysis
    self.photoStore = photoStore
    self.calendar = calendar
    self.batchSize = batchSize
  }

  /// 처음 비교·분석을 마친 뒤 보관함 변경을 반영한다. Task 가 취소되거나, 저장소가 실패하거나, 읽기 권한이 없으면 돌아온다.
  mutating func start(report: (IndexingProgress) -> Void) async {
    // 처음 조회 전에 받아 두어 그 사이 변경도 놓치지 않는다. 겹쳐 오는 변경은 식별자 집합으로 반영해 결과가 같다.
    let changes = await self.photoLibrary.imageChanges()
    do throws(IndexingStop) {
      try await self.reloadAll(report: report)
      for await change in changes {
        switch change {
        case let .incremental(inserted, removed):
          try await self.apply(inserted: inserted, removed: removed, report: report)
        case .reloadAll:
          try await self.reloadAll(report: report)
        }
      }
    } catch {
      // 취소면 저장하지 않은 분석 결과(최대 `batchSize` 장)를 버린다. 저장소 실패면 다음 실행에서 이어 한다.
      // 읽기 권한이 없으면 저장소를 그대로 둔다.
    }
  }

  // MARK: - 보관함 반영

  /// 보관함 전체를 저장소와 비교한다. 미뤘던 이미지도 다시 시도한다.
  private mutating func reloadAll(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    // 권한이 없으면 조회 결과가 비어 저장 결과가 모두 지워지므로, 비교하지 않고 멈춘다.
    guard self.photoLibrary.accessState().canRead else { throw .notReadable }
    let fetched = await self.photoLibrary.fetchImageAssets()
    self.assets = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let stored = try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.indexedIDs() }
    let libraryIDs = Set(self.assets.keys)
    try await self.delete(stored.subtracting(libraryIDs))
    self.indexedIDs = stored.intersection(libraryIDs)
    self.skippedIDs = []
    try await self.replaceTripsIfChanged()
    report(self.progress)
    // 조회 결과가 최신순이므로 최근 이미지부터 분석한다. 증분 반영처럼 같은 식별자는 한 번만 분석한다.
    var seen = Set<ImageAsset.ID>()
    let targets = fetched.filter { seen.insert($0.id).inserted && !self.indexedIDs.contains($0.id) }
    try await self.analyze(targets, report: report)
  }

  /// 증분 변경을 반영한다. 이미 반영한 변경이 다시 와도 결과가 같다.
  private mutating func apply(
    inserted: [ImageAsset],
    removed: [ImageAsset.ID],
    report: (IndexingProgress) -> Void
  ) async throws(IndexingStop) {
    let removedIDs = Set(removed)
    for id in removedIDs {
      self.assets[id] = nil
    }
    for asset in inserted {
      self.assets[asset.id] = asset
    }
    try await self.delete(removedIDs.intersection(self.indexedIDs))
    self.indexedIDs.subtract(removedIDs)
    self.skippedIDs.subtract(removedIDs)
    try await self.replaceTripsIfChanged()
    report(self.progress)

    var seen = Set<ImageAsset.ID>()
    let targets = inserted.filter { asset in
      seen.insert(asset.id).inserted && !self.indexedIDs.contains(asset.id) && !self.skippedIDs.contains(asset.id)
    }
    try await self.analyze(targets, report: report)
  }

  // MARK: - 분석

  /// 이미지를 차례로 분석하고 `batchSize` 장마다 저장하고 진행률을 보낸다.
  private mutating func analyze(
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
      switch try await self.analyze(asset) {
      case let .indexed(image):
        pending.append(image)
      case .unavailable:
        self.skippedIDs.insert(asset.id)
      case .gone:
        // 보관함에서 지워졌다. 삭제 변경도 오지만 그 전에 전체 수와 여행에서 뺀다.
        self.assets[asset.id] = nil
        foundGone = true
      }
      processedSinceReport += 1
      if processedSinceReport >= self.batchSize {
        try await self.save(&pending)
        processedSinceReport = 0
        report(self.progress)
      }
    }
    try await self.save(&pending)
    if foundGone {
      try await self.replaceTripsIfChanged()
    }
    report(self.progress)
  }

  /// 이미지 한 장을 분류 파이프라인(docs/ARCHITECTURE.md §4)으로 분석한다.
  /// ① 메타데이터 → ② 썸네일 이미지 분류 → ③ OCR 대상이면 가장 큰 버전으로 OCR → 키워드 규칙으로 카테고리.
  private func analyze(_ asset: ImageAsset) async throws(IndexingStop) -> Outcome {
    let labels: [ImageLabel]
    do throws(AnalysisFailure) {
      let thumbnail = try await self.loadImage(asset.id, size: .thumbnail)
      labels = try await self.analysis { () async throws(ImageAnalysisError) in
        try await self.imageAnalysis.classify(thumbnail)
      }
    } catch let failure {
      return try failure.outcome()
    }

    var textLines: [RecognizedTextLine]?
    if TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: labels) {
      do throws(AnalysisFailure) {
        let image = try await self.loadImage(asset.id, size: .largestAvailable)
        textLines = try await self.analysis { () async throws(ImageAnalysisError) in
          try await self.imageAnalysis.recognizeText(image)
        }
      } catch let failure {
        // 글자를 읽지 못한 채 저장하면 OCR 대상이 아니었던 이미지와 구분되지 않으므로, 이미지 전체를 미룬다.
        return try failure.outcome()
      }
    }

    let categories = RuleClassifier.classify(asset: asset, labels: labels, textLines: textLines ?? [])
    return .indexed(IndexedImage(asset: asset, labels: labels, textLines: textLines, categories: categories))
  }

  private func loadImage(_ id: ImageAsset.ID, size: ImageSize) async throws(AnalysisFailure) -> AnalysisImage {
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

  private func analysis<Output>(
    _ operation: () async throws(ImageAnalysisError) -> Output
  ) async throws(AnalysisFailure) -> Output {
    do throws(ImageAnalysisError) {
      return try await operation()
    } catch {
      switch error {
      case .cancelled: throw .cancelled
      case .failed: throw .unavailable
      }
    }
  }

  // MARK: - 저장소

  private mutating func save(_ pending: inout [IndexedImage]) async throws(IndexingStop) {
    guard !pending.isEmpty else { return }
    let images = pending
    try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.save(images) }
    self.indexedIDs.formUnion(images.map(\.id))
    pending = []
  }

  private func delete(_ ids: Set<ImageAsset.ID>) async throws(IndexingStop) {
    let ids = ids.sorted()
    for start in stride(from: 0, to: ids.count, by: self.batchSize) {
      let batch = Set(ids[start ..< min(start + self.batchSize, ids.count)])
      try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.delete(ids: batch) }
    }
  }

  /// 여행 판정은 메타데이터만 보므로 분석을 기다리지 않고 보관함이 바뀔 때마다 전체를 다시 판정한다.
  /// 이미 반영한 변경이 다시 와서 보관함이 그대로면 다시 판정·저장하지 않는다.
  private mutating func replaceTripsIfChanged() async throws(IndexingStop) {
    guard self.assets != self.judgedAssets else { return }
    let trips = TravelDetector.trips(in: Array(self.assets.values), calendar: self.calendar)
    try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.replaceTrips(trips) }
    self.judgedAssets = self.assets
  }

  private func store<Output>(
    _ operation: () async throws(PhotoStoreError) -> Output
  ) async throws(IndexingStop) -> Output {
    do {
      return try await operation()
    } catch {
      throw .storeFailed
    }
  }

  private var progress: IndexingProgress {
    IndexingProgress(
      totalCount: self.assets.count,
      indexedCount: self.indexedIDs.count,
      skippedCount: self.skippedIDs.count
    )
  }
}

/// 인덱싱을 멈추는 이유.
enum IndexingStop: Error {
  case cancelled
  case storeFailed
  /// 사진을 읽을 권한이 없다.
  case notReadable
}

/// 이미지 한 장의 분석 결과.
enum Outcome {
  case indexed(IndexedImage)
  /// 읽거나 분석하지 못했다. 저장하지 않고 미룬다.
  case unavailable
  /// 보관함에 없다.
  case gone
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
