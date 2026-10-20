import ClassifierTesting
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
  /// 분석 요청 기록. 소급 추출이 OCR 하지 않는지 확인한다.
  let analysis: ImageAnalysisClientFake
  /// 언어 모델 Fake. 기본은 쓸 수 없음이라 모델 보강 없이 규칙 결과만 저장한다.
  let classifier: ClassifierClientFake
  let indexing: IndexingClientImpl
  /// 분류에 실패하는 이미지. 테스트 도중 바꿔 다시 시도를 확인한다.
  let classifyFailures: FailingIDs
  /// OCR 에 실패하는 이미지. 테스트 도중 바꿔 다시 시도를 확인한다.
  let recognizeFailures: FailingIDs
  /// 테스트 도중 바꿀 수 있는 읽기 실패. `largestErrors` 로 시작하고, 보관함에서 사라졌다 돌아온 이미지를 흉내 낸다.
  let loadFailures: LoadFailures

  /// - Parameters:
  ///   - library: 처음 보관함 이미지.
  ///   - loadable: 나중에 변경으로 추가할 이미지. 읽기 결과만 미리 정한다.
  ///   - labels: 이미지별 분류 라벨. 없으면 `defaultLabels`(OCR 대상).
  ///   - text: 이미지별 OCR 줄. 없으면 글자 없음.
  ///   - loadErrors: 이미지별 읽기 실패.
  ///   - classifyFailures: 분류에 실패하는 이미지.
  ///   - recognizeFailures: OCR 에 실패하는 이미지.
  ///   - saveLimit: 저장소가 이 횟수만큼 저장한 뒤부터 실패한다.
  ///   - gifticonSaveLimit: 저장소가 추출 값을 이 횟수만큼 저장한 뒤부터 실패한다.
  ///   - gifticonError: 저장소의 소급 추출 호출(대상 조회·추출 값 저장)만 이 실패를 던진다.
  ///   - modelFillError: 저장소의 소급 보강 호출(대상 조회·보강 결과 저장)만 이 실패를 던진다.
  ///   - onSaveGifticons: 저장소가 추출 값을 저장하기 전에 부른다. 소급 추출 배치 도중의 일을 흉내 낸다.
  ///   - missingOnIDRead: 저장소의 식별자 읽기(`images(ids:)`)가 빼고 돌려줄 식별자.
  ///   - failingOnIDRead: 저장소의 식별자 읽기가 이 식별자를 하나라도 요청받으면 실패한다. 소급 배치 읽기만의 실패를 흉내 낸다
  ///     (소급 대상과 2단계 대상은 겹치지 않으므로 소급 대상만 넣는다).
  ///   - accessState: 사진 접근 권한.
  ///   - classifier: 언어 모델. 없으면 쓸 수 없는 Fake.
  ///   - largestErrors: 원본(`.largestAvailable`)만 읽기 실패. 2단계 실패를 흉내 낸다.
  ///   - onClassify: 이미지를 분류할 때마다 부른다. 분석 도중의 일을 흉내 낸다.
  ///   - onRecognize: 이미지를 OCR 할 때마다 결과를 주기 전에 부른다. 2단계 도중의 일을 흉내 낸다.
  ///   - changeRequests: 주면 인덱서가 보관함 변경을 요청한 횟수를 센다. 2단계·소급 추출 도중 보낸 변경이
  ///     인덱서에 닿은 뒤에 OCR·저장을 끝내게 해, 변경을 다음 배치 경계에서 반영하는지 시점에 기대지 않고 확인한다.
  init(
    library: [ImageAsset],
    loadable: [ImageAsset] = [],
    stored: [IndexedImage] = [],
    labels: [ImageAsset.ID: [ImageLabel]] = [:],
    text: [ImageAsset.ID: [String]] = [:],
    loadErrors: [ImageAsset.ID: ImageLoadError] = [:],
    largestErrors: [ImageAsset.ID: ImageLoadError] = [:],
    classifyFailures: Set<ImageAsset.ID> = [],
    recognizeFailures: Set<ImageAsset.ID> = [],
    onClassify: @escaping @Sendable (ImageAsset.ID) -> Void = { _ in },
    onRecognize: @escaping @Sendable (ImageAsset.ID) async -> Void = { _ in },
    storeError: PhotoStoreError? = nil,
    saveLimit: Int? = nil,
    gifticonSaveLimit: Int? = nil,
    gifticonError: PhotoStoreError? = nil,
    modelFillError: PhotoStoreError? = nil,
    onSaveGifticons: @escaping @Sendable ([ImageAsset.ID: GifticonInfo]) async -> Void = { _ in },
    missingOnIDRead: Set<ImageAsset.ID> = [],
    failingOnIDRead: Set<ImageAsset.ID> = [],
    accessState: PhotoAccessState = .authorized,
    classifier: ClassifierClientFake = ClassifierClientFake(isModelAvailable: false),
    batchSize: Int = IndexingClientImpl.defaultBatchSize,
    textBatchSize: Int = IndexingClientImpl.defaultTextBatchSize,
    changeRequests: ChangeRequests? = nil
  ) {
    let ids = (library + loadable).map(\.id)
    let widths = Dictionary(ids.enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    let idsByWidth = Dictionary(widths.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    self.photoLibrary = Self.photoLibrary(library, widths: widths, loadErrors: loadErrors, accessState: accessState)
    self.store = PhotoStoreClientFake(
      images: stored,
      error: storeError,
      saveLimit: saveLimit,
      gifticonSaveLimit: gifticonSaveLimit,
      gifticonError: gifticonError,
      modelFillError: modelFillError,
      missingOnIDRead: missingOnIDRead,
      failingOnIDRead: failingOnIDRead,
      onSaveGifticons: onSaveGifticons
    )
    let failing = FailingIDs(classifyFailures)
    self.classifyFailures = failing
    let failingText = FailingIDs(recognizeFailures)
    self.recognizeFailures = failingText
    let loadFailures = LoadFailures(largest: largestErrors)
    self.loadFailures = loadFailures
    self.classifier = classifier
    self.analysis = ImageAnalysisClientFake(
      classify: { image in
        let id = idsByWidth[image.cgImage.width] ?? ""
        onClassify(id)
        return failing.contains(id) ? .failure(.failed) : .success(labels[id] ?? defaultLabels)
      },
      recognizeText: Self.recognizer(
        idsByWidth: idsByWidth,
        text: text,
        failures: failingText,
        onRecognize: onRecognize
      )
    )
    self.indexing = IndexingClientImpl(
      photoLibrary: LargestFailingPhotoLibrary(
        base: self.photoLibrary,
        loadFailures: loadFailures,
        changeRequests: changeRequests
      ),
      imageAnalysis: self.analysis,
      photoStore: self.store,
      classifier: classifier,
      calendar: Self.seoulCalendar,
      batchSize: batchSize,
      textBatchSize: textBatchSize
    )
  }
}

extension Fixture {
  /// 보관함 Fake. 이미지마다 `widths` 폭의 썸네일을 돌려주고, `loadErrors` 가 있으면 그 실패를 던진다.
  static func photoLibrary(
    _ library: [ImageAsset],
    widths: [ImageAsset.ID: Int],
    loadErrors: [ImageAsset.ID: ImageLoadError],
    accessState: PhotoAccessState
  ) -> PhotoLibraryClientFake {
    PhotoLibraryClientFake(
      currentState: accessState,
      imageAssets: library,
      loadImageResults: widths.reduce(into: [:]) { results, entry in
        results[entry.key] = loadErrors[entry.key].map { .failure($0) } ?? .success(.stub(
          width: entry.value,
          height: 1
        ))
      }
    )
  }

  /// OCR Fake 의 결과. 폭으로 이미지를 찾아 `onRecognize` 를 부른 뒤 `failures`·`text` 로 고른다.
  static func recognizer(
    idsByWidth: [Int: ImageAsset.ID],
    text: [ImageAsset.ID: [String]],
    failures: FailingIDs,
    onRecognize: @escaping @Sendable (ImageAsset.ID) async -> Void
  ) -> @Sendable (AnalysisImage) async -> Result<[RecognizedTextLine], ImageAnalysisError> {
    { image in
      let id = idsByWidth[image.cgImage.width] ?? ""
      await onRecognize(id)
      if failures.contains(id) {
        return .failure(.failed)
      }
      return .success(ocrLines(text[id] ?? []))
    }
  }

  static var seoulCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
  }
}

/// PhotoLibrary Fake 는 크기와 관계없이 같은 결과를 정해 두므로, 원본만 실패하거나 테스트 도중 바뀌는 실패(`loadFailures`)를 이 대역이 더한다.
/// 요청은 Fake 에 기록된다. `changeRequests` 를 주면 받는 쪽이 변경을 하나 요청할 때마다 센다.
struct LargestFailingPhotoLibrary: PhotoLibraryClient {
  let base: PhotoLibraryClientFake
  let loadFailures: LoadFailures
  let changeRequests: ChangeRequests?

  func accessState() -> PhotoAccessState {
    self.base.accessState()
  }

  func requestAccess() async -> PhotoAccessState {
    await self.base.requestAccess()
  }

  func fetchImageAssets() async -> [ImageAsset] {
    await self.base.fetchImageAssets()
  }

  func fetchImageAssets(inAlbumNamed name: String) async -> [ImageAsset]? {
    await self.base.fetchImageAssets(inAlbumNamed: name)
  }

  func loadImage(id: ImageAsset.ID, size: ImageSize) async throws(ImageLoadError) -> AnalysisImage {
    if let error = self.loadFailures.error(for: id, size: size) {
      _ = try? await self.base.loadImage(id: id, size: size)
      throw error
    }
    return try await self.base.loadImage(id: id, size: size)
  }

  @MainActor
  func presentLimitedLibraryPicker() async {
    await self.base.presentLimitedLibraryPicker()
  }

  /// 인덱서의 변경 받기 Task 는 받은 변경을 수신함에 넣은 뒤에 다음 변경을 요청한다.
  /// 그래서 요청 횟수가 (보낸 변경 수 + 1) 이 되면 보낸 변경이 모두 수신함에 들어갔다.
  func imageChanges() async -> AsyncStream<ImageChange> {
    let changes = await self.base.imageChanges()
    guard let changeRequests = self.changeRequests else { return changes }
    let iterator = ChangeIterator(changes.makeAsyncIterator())
    return AsyncStream {
      changeRequests.record()
      return await iterator.next()
    }
  }
}

/// 변경 스트림의 반복자를 요청 사이에 들고 있다. 반복자는 Sendable 이 아니라 actor 안에 둔다.
private actor ChangeIterator {
  private var iterator: AsyncStream<ImageChange>.Iterator

  init(_ iterator: AsyncStream<ImageChange>.Iterator) {
    self.iterator = iterator
  }

  func next() async -> ImageChange? {
    var iterator = self.iterator
    let change = await iterator.next(isolation: self)
    self.iterator = iterator
    return change
  }
}

/// 이미지별 읽기 실패. 원본만 실패하거나 두 크기 모두 실패한다. Fake 의 읽기가 다른 Task 에서 읽으므로 Mutex 로 보호한다.
final class LoadFailures: Sendable {
  private struct Failure {
    let error: ImageLoadError
    let largestOnly: Bool
  }

  private let failures: Mutex<[ImageAsset.ID: Failure]>

  init(largest: [ImageAsset.ID: ImageLoadError]) {
    self.failures = Mutex(largest.mapValues { Failure(error: $0, largestOnly: true) })
  }

  /// 두 크기 모두 실패하게 한다.
  func setAllSizes(_ id: ImageAsset.ID, _ error: ImageLoadError) {
    self.failures.withLock { $0[id] = Failure(error: error, largestOnly: false) }
  }

  func remove(_ id: ImageAsset.ID) {
    self.failures.withLock { _ = $0.removeValue(forKey: id) }
  }

  func error(for id: ImageAsset.ID, size: ImageSize) -> ImageLoadError? {
    self.failures.withLock { failures in
      guard let failure = failures[id], !failure.largestOnly || size == .largestAvailable else { return nil }
      return failure.error
    }
  }
}

/// 받는 쪽이 보관함 변경을 요청한 횟수. 변경 받기 Task 가 늘리고 테스트의 OCR 훅이 기다린다.
final class ChangeRequests: Sendable {
  private let count = Mutex(0)

  func record() {
    self.count.withLock { $0 += 1 }
  }

  /// 요청이 `count` 번이 될 때까지 기다린다.
  func wait(until count: Int) async {
    while self.count.withLock({ $0 }) < count, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(1))
    }
  }
}

/// 테스트가 Fixture 를 만든 뒤에 채우는 값. Fake 의 클로저가 다른 Task 에서 읽으므로 Mutex 로 보호한다.
final class Later<Value: Sendable>: Sendable {
  private let value = Mutex<Value?>(nil)

  func set(_ value: Value) {
    self.value.withLock { $0 = value }
  }

  var current: Value? {
    self.value.withLock { $0 }
  }
}

/// 열릴 때까지 기다리는 문. Fake 가 다른 Task 에서 기다리고 테스트가 연다.
final class Gate: Sendable {
  private let isOpen = Mutex(false)

  func open() {
    self.isOpen.withLock { $0 = true }
  }

  func wait() async {
    while !self.isOpen.withLock({ $0 }), !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(1))
    }
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

func indexed(_ id: String) -> IndexedImage {
  IndexedImage(asset: .stub(id: id), labels: [], textRecognition: .notNeeded, categories: [.other])
}

/// 1단계를 마치고 OCR 을 기다리는 저장 결과.
func pending(_ asset: ImageAsset, labels: [ImageLabel] = []) -> IndexedImage {
  IndexedImage(
    asset: asset,
    labels: labels,
    textRecognition: .pending,
    categories: IndexingRun.pendingCategories(asset: asset, labels: labels)
  )
}

/// OCR Fake 가 돌려주는 줄. 소급 추출 테스트의 저장된 줄도 같은 모양으로 만든다.
func ocrLines(_ texts: [String]) -> [RecognizedTextLine] {
  texts.map { RecognizedTextLine(text: $0, confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1)) }
}

/// 2단계에서 `.largestAvailable` 로 읽은 식별자를 순서대로.
extension PhotoLibraryClientFake {
  var largestLoadIDs: [ImageAsset.ID] {
    self.loadImageRequests.filter { $0.size == .largestAvailable }.map(\.id)
  }
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

/// `Fixture` 에서 라벨을 정하지 않은 이미지의 분류 라벨. 위치·글자 라벨이 없는 기본 스텁도 OCR 대상이 되게 한다.
/// 사진형·정보형 카테고리를 정하지 않으므로 카테고리는 OCR 줄로만 정해진다.
let defaultLabels = [ImageLabel(identifier: "screenshot", confidence: 0.9)]
