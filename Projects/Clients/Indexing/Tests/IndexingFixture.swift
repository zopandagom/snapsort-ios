import Core
import CoreGraphics
import Foundation
import ImageAnalysisInterface
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
@testable import IndexingImpl

// IndexingClientImplTests 의 테스트 준비.

let seoul = Coordinate(latitude: 37.5665, longitude: 126.978)

/// 분석 Fake 는 이미지 픽셀만 받으므로, 이미지마다 썸네일 폭을 달리해 어떤 이미지인지 알게 한다.
struct Fixture {
  let photoLibrary: PhotoLibraryClientFake
  let store: PhotoStoreClientFake
  let indexing: IndexingClientImpl
  /// 분류에 실패하는 이미지. 테스트 도중 바꿔 다시 시도를 확인한다.
  let classifyFailures: FailingIDs

  /// - Parameters:
  ///   - library: 처음 보관함 이미지.
  ///   - loadable: 나중에 변경으로 추가할 이미지. 읽기 결과만 미리 정한다.
  ///   - labels: 이미지별 분류 라벨. 없으면 라벨 없음.
  ///   - text: 이미지별 OCR 줄. 없으면 글자 없음.
  ///   - loadErrors: 이미지별 읽기 실패.
  ///   - classifyFailures: 분류에 실패하는 이미지.
  ///   - recognizeFailures: OCR 에 실패하는 이미지.
  ///   - saveLimit: 저장소가 이 횟수만큼 저장한 뒤부터 실패한다.
  ///   - accessState: 사진 접근 권한.
  ///   - onClassify: 이미지를 분류할 때마다 부른다. 분석 도중의 일을 흉내 낸다.
  init(
    library: [ImageAsset],
    loadable: [ImageAsset] = [],
    stored: [IndexedImage] = [],
    labels: [ImageAsset.ID: [ImageLabel]] = [:],
    text: [ImageAsset.ID: [String]] = [:],
    loadErrors: [ImageAsset.ID: ImageLoadError] = [:],
    classifyFailures: Set<ImageAsset.ID> = [],
    recognizeFailures: Set<ImageAsset.ID> = [],
    onClassify: @escaping @Sendable (ImageAsset.ID) -> Void = { _ in },
    storeError: PhotoStoreError? = nil,
    saveLimit: Int? = nil,
    accessState: PhotoAccessState = .authorized,
    batchSize: Int = IndexingClientImpl.defaultBatchSize
  ) {
    let ids = (library + loadable).map(\.id)
    let widths = Dictionary(ids.enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    let idsByWidth = Dictionary(widths.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    var loadResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = [:]
    for (id, width) in widths {
      loadResults[id] = loadErrors[id].map { .failure($0) } ?? .success(.stub(width: width, height: 1))
    }

    self.photoLibrary = PhotoLibraryClientFake(
      currentState: accessState,
      imageAssets: library,
      loadImageResults: loadResults
    )
    self.store = PhotoStoreClientFake(images: stored, error: storeError, saveLimit: saveLimit)
    let failing = FailingIDs(classifyFailures)
    self.classifyFailures = failing
    let analysis = ImageAnalysisClientFake(
      classify: { image in
        let id = idsByWidth[image.cgImage.width] ?? ""
        onClassify(id)
        return failing.contains(id) ? .failure(.failed) : .success(labels[id] ?? [])
      },
      recognizeText: { image in
        let id = idsByWidth[image.cgImage.width] ?? ""
        if recognizeFailures.contains(id) {
          return .failure(.failed)
        }
        return .success((text[id] ?? []).map {
          RecognizedTextLine(text: $0, confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1))
        })
      }
    )
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    self.indexing = IndexingClientImpl(
      photoLibrary: self.photoLibrary,
      imageAnalysis: analysis,
      photoStore: self.store,
      calendar: calendar,
      batchSize: batchSize
    )
  }
}

/// 테스트 도중 바꿀 수 있는 실패 대상. 분석 Fake 의 결과 클로저가 다른 Task 에서 읽으므로 Mutex 로 보호한다.
final class FailingIDs: Sendable {
  private let ids: Mutex<Set<ImageAsset.ID>>

  init(_ ids: Set<ImageAsset.ID>) {
    self.ids = Mutex(ids)
  }

  func contains(_ id: ImageAsset.ID) -> Bool {
    self.ids.withLock { $0.contains(id) }
  }

  func removeAll() {
    self.ids.withLock { $0.removeAll() }
  }
}

/// 분석 도중 분석 Fake 에서 끝낼 수 있는 구독 Task.
final class ConsumerTask: Sendable {
  private let task = Mutex<Task<Void, Never>?>(nil)

  func start(_ operation: @escaping @Sendable () async -> Void) {
    self.task.withLock { $0 = Task(operation: operation) }
  }

  func cancel() {
    self.task.withLock { $0?.cancel() }
  }

  func wait() async {
    await self.task.withLock { $0 }?.value
  }
}

func indexed(_ id: String) -> IndexedImage {
  IndexedImage(asset: .stub(id: id), labels: [], textLines: nil, categories: [.other])
}

func date(month: Int, day: Int) -> Date {
  var components = DateComponents(year: 2026, month: month, day: day, hour: 10)
  components.timeZone = TimeZone(identifier: "Asia/Seoul")
  return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
}

extension AsyncStream<IndexingProgress>.Iterator {
  /// 조건에 맞는 진행률이 올 때까지 기다린다. 스트림이 끝나면 nil.
  mutating func next(where predicate: (IndexingProgress) -> Bool) async -> IndexingProgress? {
    while let progress = await self.next() {
      if predicate(progress) {
        return progress
      }
    }
    return nil
  }
}

extension Array {
  /// 원소가 하나뿐이면 그 원소.
  var only: Element? {
    self.count == 1 ? self.first : nil
  }
}
