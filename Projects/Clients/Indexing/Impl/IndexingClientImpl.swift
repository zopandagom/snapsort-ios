import ClassifierInterface
import Core
import Foundation
import ImageAnalysisInterface
import IndexingInterface
import PhotoLibraryInterface
import PhotoStoreInterface

/// 다른 Client 를 조합한 구현. 이 모듈은 Apple 데이터 프레임워크를 직접 쓰지 않는다.
public struct IndexingClientImpl: IndexingClient {
  /// 1단계(분류)에서 한 번에 저장·삭제하는 이미지 수. 저장소는 식별자 목록 조건(`ids.contains`)으로 기존 행을 찾으므로 조건 크기를 이 수로 묶고,
  /// 중간에 멈춰도 이 수만큼만 다시 분석하게 한다. 소급 추출도 같은 저장소 조건을 쓰므로 이 수로 나눠 읽고 저장한다.
  /// 임시 값이며 1만 장 측정 작업에서 확정한다.
  static let defaultBatchSize = 50
  /// 2단계(OCR)에서 한 번에 읽어 저장하는 이미지 수. OCR 은 장당 약 1초라 이 수마다 저장·진행률·개수가 갱신되고,
  /// 멈춰도 이 수만큼만 다시 OCR 한다. 보관함 변경도 이 배치 경계에서 먼저 반영한다. 임시 값이며 실기기에서 조정한다.
  /// 소급 보강도 모델 호출이 OCR 과 같은 단위로 느려 이 수로 나눠 읽고 저장한다.
  static let defaultTextBatchSize = 10

  private let photoLibrary: any PhotoLibraryClient
  private let imageAnalysis: any ImageAnalysisClient
  private let photoStore: any PhotoStoreClient
  private let classifier: any ClassifierClient
  private let calendar: Calendar
  private let batchSize: Int
  private let textBatchSize: Int

  /// - Parameter classifier: 2단계의 분류 보강(규칙 분류가 기타뿐인 이미지)과 기프티콘 추출 보강에 쓰는 언어 모델.
  ///   모델을 쓸 수 없으면 규칙 결과만 저장한다.
  /// - Parameter calendar: 날짜를 나누는 달력. 여행 판정과 기프티콘 추출(2단계·소급 추출에서 이미지 생성일의 날짜를 정해
  ///   연도를 생략한 만료일의 기준일로 쓴다)에 쓴다. 앱은 기기 달력을 넘긴다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    imageAnalysis: any ImageAnalysisClient,
    photoStore: any PhotoStoreClient,
    classifier: any ClassifierClient,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.init(
      photoLibrary: photoLibrary,
      imageAnalysis: imageAnalysis,
      photoStore: photoStore,
      classifier: classifier,
      calendar: calendar,
      batchSize: Self.defaultBatchSize,
      textBatchSize: Self.defaultTextBatchSize
    )
  }

  init(
    photoLibrary: any PhotoLibraryClient,
    imageAnalysis: any ImageAnalysisClient,
    photoStore: any PhotoStoreClient,
    classifier: any ClassifierClient,
    calendar: Calendar,
    batchSize: Int,
    textBatchSize: Int
  ) {
    self.photoLibrary = photoLibrary
    self.imageAnalysis = imageAnalysis
    self.photoStore = photoStore
    self.classifier = classifier
    self.calendar = calendar
    self.batchSize = max(batchSize, 1)
    self.textBatchSize = max(textBatchSize, 1)
  }

  /// 화면 응답을 막지 않도록 낮은 우선순위(`.utility`)로 메인 밖에서 분석한다.
  public func run() -> AsyncStream<IndexingProgress> {
    let (stream, continuation) = AsyncStream.makeStream(of: IndexingProgress.self, bufferingPolicy: .bufferingNewest(1))
    let task = Task(priority: .utility) { [self] in
      var indexing = self.makeRun()
      await indexing.start { continuation.yield($0) }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  /// `run()` 한 번의 상태를 만든다. 테스트는 진행률을 버리지 않고 모두 받으려고 이것으로 직접 돌린다
  /// (`run()` 스트림은 늦게 읽으면 지난 값을 버린다).
  func makeRun() -> IndexingRun {
    IndexingRun(
      photoLibrary: self.photoLibrary,
      imageAnalysis: self.imageAnalysis,
      photoStore: self.photoStore,
      classifier: self.classifier,
      calendar: self.calendar,
      batchSize: self.batchSize,
      textBatchSize: self.textBatchSize
    )
  }
}

/// `run()` 한 번의 상태. 한 Task 안에서만 쓴다. 단계별 분석은 IndexingRun+Stages.swift, 소급은 IndexingRun+Gifticon.swift·
/// IndexingRun+ModelFill.swift 에 있다.
struct IndexingRun {
  let photoLibrary: any PhotoLibraryClient
  let imageAnalysis: any ImageAnalysisClient
  let photoStore: any PhotoStoreClient
  let classifier: any ClassifierClient
  let calendar: Calendar
  let batchSize: Int
  let textBatchSize: Int

  /// 보관함 이미지. 여행 판정과 전체 수에 쓴다.
  var assets: [ImageAsset.ID: ImageAsset] = [:]
  /// 저장소에 결과가 있는 이미지(OCR 대기 포함). 2단계에서 보관함에 없다고(`notFound`) 나와도 남긴다.
  /// 나중에 오는 삭제 변경이 `removed ∩ indexedIDs` 로 행을 지우고, 다시 추가되면 대기로 되돌리는 데(`goneTextIDs`) 필요하다.
  /// 그래서 진행률은 보관함에 있는 것만 센다. 2단계에서 저장 결과가 없다고 나온 이미지는 뺀다(1단계 미룸으로 옮긴다).
  var indexedIDs: Set<ImageAsset.ID> = []
  /// 이번 실행 1단계에서 미룬 이미지. 전체 다시 비교(`.reloadAll`)나 다음 실행에서 다시 시도한다.
  var skippedIDs: Set<ImageAsset.ID> = []
  /// 저장됐고 OCR 을 기다리며 이번 실행에서 미루지 않은 보관함 이미지. 2단계가 할 일이다.
  var pendingTextIDs: Set<ImageAsset.ID> = []
  /// 이번 실행 2단계에서 미룬 이미지. 같은 실행에서 다시 하지 않고 전체 다시 비교에서 비운다(다시 시도).
  var textSkippedIDs: Set<ImageAsset.ID> = []
  /// 2단계에서 보관함에 없다고(`notFound`) 나와 대기에서 뺐지만 저장 행은 대기로 남은 이미지.
  /// 삭제 변경이 오면 빼고(행은 삭제 경로가 지운다), 삭제 없이 다시 추가되면 대기로 되돌린다. 전체 다시 비교에서 비운다(저장소에서 다시 채운다).
  var goneTextIDs: Set<ImageAsset.ID> = []
  /// 기프티콘으로 분류돼 글자를 읽었지만 지금 규칙 버전으로 추출하지 않은 보관함 이미지. 저장된 줄로 소급 추출한다(IndexingRun+Gifticon.swift).
  /// 2단계 대기(읽기 전 행)와 겹치지 않는다. 진행률에는 넣지 않는다.
  /// 저장소 실패로 이번 실행의 소급을 멈추면 비우고, 전체 다시 비교(`reloadAll`)가 저장소에서 다시 채운다.
  var pendingGifticonIDs: Set<ImageAsset.ID> = []
  /// 추출 값의 언어 모델 보강을 마치지 않은 기프티콘(`GifticonModelFill.pending`·`.stale`) 보관함 이미지. 저장된 줄로 소급 보강한다
  /// (IndexingRun+ModelFill.swift). 모델을 쓸 수 있는지와 관계없이 채운다(`.stale` 행 되돌리기와 채울 필드가 없는 행 마치기는 모델 없이 한다).
  /// 소급 추출 대상과 겹치지 않는다. 진행률에는 넣지 않는다. 저장소 실패로 멈추면 비우고, 전체 다시 비교가 다시 채운다.
  var pendingModelFillIDs: Set<ImageAsset.ID> = []
  /// 이번 실행에서 모델이 잇달아 실패한 수. 모델이 답하면 0 으로 되돌린다.
  var consecutiveModelFailures = 0
  /// 모델이 잇달아 실패해 이번 실행(다음 전체 다시 비교까지)에서는 모델을 부르지 않는다.
  /// 시뮬레이터처럼 쓸 수 있다고 하는데 요청이 모두 실패하는 환경에서 이미지마다 실패를 기다리지 않게 한다.
  var isModelSuspended = false
  /// 이번 실행에서 글자를 읽어 저장한 수.
  var recognizedTextCount = 0
  /// 마지막으로 여행을 판정한 보관함. 같은 보관함으로 다시 판정·저장하지 않으려고 둔다.
  var judgedAssets: [ImageAsset.ID: ImageAsset]?

  init(
    photoLibrary: any PhotoLibraryClient,
    imageAnalysis: any ImageAnalysisClient,
    photoStore: any PhotoStoreClient,
    classifier: any ClassifierClient,
    calendar: Calendar,
    batchSize: Int,
    textBatchSize: Int
  ) {
    self.photoLibrary = photoLibrary
    self.imageAnalysis = imageAnalysis
    self.photoStore = photoStore
    self.classifier = classifier
    self.calendar = calendar
    self.batchSize = batchSize
    self.textBatchSize = textBatchSize
  }

  /// 처음 비교·1단계를 마친 뒤 보관함 변경, 소급 추출, 2단계, 소급 보강을 번갈아 한다.
  /// Task 가 취소되거나, 저장소가 실패하거나(소급 추출·소급 보강만의 실패는 빼고), 읽기 권한이 없으면 돌아온다.
  /// 모델을 쓸 수 없거나 모델이 실패해도 멈추지 않는다(규칙 결과로 이어 간다).
  /// 변경은 자식 Task 가 받아 수신함에 쌓고, 본 루프가 소급 추출·2단계·소급 보강 배치 경계에서 꺼내 먼저 반영한다.
  /// 본 루프가 어느 경로로 끝나든 자식을 취소한다. 저장소 실패·권한 없음은 부모 Task 가 취소되지 않은 채 끝나므로,
  /// 취소하지 않으면 자식이 끝나지 않는 변경 스트림에 머물러 `run()` 스트림이 끝나지 않는다.
  mutating func start(report: (IndexingProgress) -> Void) async {
    // 처음 조회 전에 받아 두어 그 사이 변경도 놓치지 않는다. 겹쳐 오는 변경은 식별자 집합으로 반영해 결과가 같다.
    let changes = await self.photoLibrary.imageChanges()
    let inbox = ChangeInbox()
    let (signals, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    await withDiscardingTaskGroup { group in
      group.addTask {
        for await change in changes {
          inbox.append(change)
          signal.yield()
        }
        inbox.finish()
        signal.yield()
      }
      do throws(IndexingStop) {
        try await self.loop(inbox: inbox, signals: signals, report: report)
      } catch {
        // 취소면 저장하지 않은 결과(1단계 최대 `batchSize`, 2단계·소급 보강 최대 `textBatchSize` 장)를 버린다.
        // 저장소 실패면 다음 실행에서 이어 한다. 읽기 권한이 없으면 저장소를 그대로 둔다.
      }
      group.cancelAll()
    }
  }

  /// 변경이 있으면 먼저 반영하고, 없으면 소급 추출 한 배치, 그것도 없으면 2단계 한 배치, 그것도 없으면 소급 보강 한 배치를 하고,
  /// 모두 없으면 변경을 기다린다. 소급 추출은 OCR 없이 저장된 줄로 하는 순수 계산이라 OCR 보다 훨씬 짧으므로 먼저 한다.
  /// 소급 보강은 모델 호출이라 OCR 과 같은 단위로 느리므로, 카테고리·개수를 바꾸는 2단계를 마친 뒤에 한다.
  /// 변경 스트림이 끝났으면 남은 변경·소급 추출·2단계·소급 보강을 마친 뒤 돌아온다.
  private mutating func loop(
    inbox: ChangeInbox,
    signals: AsyncStream<Void>,
    report: (IndexingProgress) -> Void
  ) async throws(IndexingStop) {
    try await self.reloadAll(report: report)
    var waiting = signals.makeAsyncIterator()
    while true {
      if Task.isCancelled {
        throw .cancelled
      }
      let (changes, isFinished) = inbox.takeAll()
      if !changes.isEmpty {
        for change in changes {
          switch change {
          case let .incremental(inserted, removed):
            try await self.apply(inserted: inserted, removed: removed, report: report)
          case .reloadAll:
            try await self.reloadAll(report: report)
          }
        }
      } else if !self.pendingGifticonIDs.isEmpty {
        try await self.extractGifticonBatch(report: report)
      } else if !self.pendingTextIDs.isEmpty {
        try await self.recognizeBatch(report: report)
      } else if !self.pendingModelFillIDs.isEmpty {
        try await self.fillGifticonBatch(report: report)
      } else if isFinished {
        return
      } else {
        _ = await waiting.next()
      }
    }
  }

  // MARK: - 보관함 반영

  /// 보관함 전체를 저장소와 비교한다. 미뤘던 이미지(1·2단계)와 이번 실행에서 멈춘 모델 호출(연속 실패)도 다시 시도한다.
  mutating func reloadAll(report: (IndexingProgress) -> Void) async throws(IndexingStop) {
    // 권한이 없으면 조회 결과가 비어 저장 결과가 모두 지워지므로, 비교하지 않고 멈춘다.
    guard self.photoLibrary.accessState().canRead else { throw .notReadable }
    let fetched = await self.photoLibrary.fetchImageAssets()
    self.assets = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let stored = try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.indexedIDs() }
    let pending = try await self.store { () async throws(PhotoStoreError) in
      try await self.photoStore.pendingTextRecognitionIDs()
    }
    let pendingGifticons: Set<ImageAsset.ID>
    do throws(IndexingStop) {
      pendingGifticons = try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.gifticonExtractionPendingIDs()
      }
    } catch {
      // 소급 대상 조회만 실패하면 이번 비교에서는 소급만 하지 않고 비교·분류는 이어 간다(`extractGifticonBatch` 와 같은 이유).
      guard error == .storeFailed else { throw error }
      pendingGifticons = []
    }
    let pendingModelFills: Set<ImageAsset.ID>
    do throws(IndexingStop) {
      pendingModelFills = try await self.store { () async throws(PhotoStoreError) in
        try await self.photoStore.gifticonModelFillPendingIDs()
      }
    } catch {
      // 소급 보강 대상 조회만 실패하면 소급 추출과 같이 이번 비교에서는 소급 보강만 하지 않는다(`fillGifticonBatch`).
      guard error == .storeFailed else { throw error }
      pendingModelFills = []
    }
    let libraryIDs = Set(self.assets.keys)
    // 첫 진행률부터 대기 수가 들어가도록 보고 전에 채운다. 늦게 채우면 재시작 직후 다 끝난 것처럼 보였다가 다시 진행 중이 된다.
    self.indexedIDs = stored.intersection(libraryIDs)
    self.pendingTextIDs = pending.intersection(libraryIDs)
    self.pendingGifticonIDs = pendingGifticons.intersection(libraryIDs)
    self.pendingModelFillIDs = pendingModelFills.intersection(libraryIDs)
    self.consecutiveModelFailures = 0
    self.isModelSuspended = false
    self.skippedIDs = []
    self.textSkippedIDs = []
    self.goneTextIDs = []
    try await self.delete(stored.subtracting(libraryIDs))
    try await self.replaceTripsIfChanged()
    report(self.progress)
    // 조회 결과가 최신순이므로 최근 이미지부터 분류한다. 증분 반영처럼 같은 식별자는 한 번만 분류한다.
    var seen = Set<ImageAsset.ID>()
    let targets = fetched.filter { seen.insert($0.id).inserted && !self.indexedIDs.contains($0.id) }
    try await self.classifyAll(targets, report: report)
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
    self.pendingTextIDs.subtract(removedIDs)
    self.pendingGifticonIDs.subtract(removedIDs)
    self.pendingModelFillIDs.subtract(removedIDs)
    self.textSkippedIDs.subtract(removedIDs)
    self.goneTextIDs.subtract(removedIDs)
    // 삭제를 먼저 반영했으므로, 같은 변경에 삭제와 추가가 함께 오면 행이 지워져 아래 1단계 대상이 된다.
    let insertedIDs = Set(inserted.map(\.id))
    self.pendingTextIDs.formUnion(insertedIDs.intersection(self.goneTextIDs).intersection(self.indexedIDs))
    self.goneTextIDs.subtract(insertedIDs)
    try await self.replaceTripsIfChanged()
    report(self.progress)

    var seen = Set<ImageAsset.ID>()
    let targets = inserted.filter { asset in
      seen.insert(asset.id).inserted && !self.indexedIDs.contains(asset.id) && !self.skippedIDs.contains(asset.id)
    }
    try await self.classifyAll(targets, report: report)
  }

  // MARK: - 저장소

  func delete(_ ids: Set<ImageAsset.ID>) async throws(IndexingStop) {
    let ids = ids.sorted()
    for start in stride(from: 0, to: ids.count, by: self.batchSize) {
      let batch = Set(ids[start ..< min(start + self.batchSize, ids.count)])
      try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.delete(ids: batch) }
    }
  }

  /// 여행 판정은 메타데이터만 보므로 분석을 기다리지 않고 보관함이 바뀔 때마다 전체를 다시 판정한다.
  /// 이미 반영한 변경이 다시 와서 보관함이 그대로면 다시 판정·저장하지 않는다.
  mutating func replaceTripsIfChanged() async throws(IndexingStop) {
    guard self.assets != self.judgedAssets else { return }
    let trips = TravelDetector.trips(in: Array(self.assets.values), calendar: self.calendar)
    try await self.store { () async throws(PhotoStoreError) in try await self.photoStore.replaceTrips(trips) }
    self.judgedAssets = self.assets
  }

  func store<Output>(
    _ operation: () async throws(PhotoStoreError) -> Output
  ) async throws(IndexingStop) -> Output {
    do {
      return try await operation()
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

/// 인덱싱을 멈추는 이유.
enum IndexingStop: Error {
  case cancelled
  case storeFailed
  /// 사진을 읽을 권한이 없다.
  case notReadable
}
