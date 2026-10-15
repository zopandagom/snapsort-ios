#if DEBUG
  import Core
  import CoreGraphics
  import Foundation
  import ImageAnalysisInterface
  import ImageAnalysisTesting
  import PhotoLibraryInterface
  import PhotoLibraryTesting
  import Synchronization
  import Testing
  @testable import SampleRecorderFeature

  // SampleRecorderModelTests 의 테스트 준비.

  let seoul = Coordinate(latitude: 37.5665, longitude: 126.978)
  let normalConditions = DeviceConditions(thermalState: .nominal, isLowPowerModeEnabled: false)

  /// 분석 Fake 는 이미지 픽셀만 받으므로, 이미지마다 썸네일 폭을 달리해 어떤 이미지인지 알게 한다.
  /// 이미지 읽기·분석 호출을 한 기록(`log`)에 남겨 단계 순서를 확인한다.
  @MainActor
  struct RecorderFixture {
    let model: SampleRecorderModel
    let photoLibrary: PhotoLibraryClientFake
    let imageAnalysis: ImageAnalysisClientFake
    let log: EventLog

    /// - Parameters:
    ///   - album: 앨범 "SnapSort 샘플" 의 이미지. nil 이면 앨범이 없다.
    ///   - library: 보관함 이미지(최신순).
    ///   - loadErrors: 이미지별 읽기 실패 (두 크기 모두).
    ///   - largestErrors: 원본(`.largestAvailable`)만 읽기 실패.
    ///   - fallbackIDs: iCloud 대체 버전으로 읽히는 이미지.
    ///   - classifyGate: 분류 결과를 주기 전에 부른다. 측정 도중의 취소를 흉내 낸다.
    ///   - largestImages: 원본(`.largestAvailable`)으로 이 이미지를 준다. OCR 해상도 비교에서 줄일 만큼 큰 원본을 흉내 낸다.
    ///   - recognizeBySize: OCR 입력 크기(폭·높이)로 결과를 고른다. nil 을 돌려주면 폭으로 이미지를 찾는 기본 규칙을 쓴다.
    ///     줄인 이미지는 폭이 바뀌어 기본 규칙으로 찾지 못하기 때문이다. 설정하면 OCR 기록은 `ocr:<폭>x<높이>` 다.
    ///   - fetchGate: 보관함·앨범 조회가 결과를 주기 전에 부른다.
    ///   - loadGate: 이미지 읽기가 결과를 주기 전에 식별자를 넘겨 부른다.
    init(
      access: PhotoAccessState = .authorized,
      album: [ImageAsset]? = nil,
      library: [ImageAsset] = [],
      labels: [ImageAsset.ID: [ImageLabel]] = [:],
      text: [ImageAsset.ID: [String]] = [:],
      loadErrors: [ImageAsset.ID: ImageLoadError] = [:],
      largestErrors: [ImageAsset.ID: ImageLoadError] = [:],
      fallbackIDs: Set<ImageAsset.ID> = [],
      classifyFailures: Set<ImageAsset.ID> = [],
      recognizeFailures: Set<ImageAsset.ID> = [],
      classifyGate: @escaping @Sendable (ImageAsset.ID) async -> Void = { _ in },
      largestImages: [ImageAsset.ID: AnalysisImage] = [:],
      recognizeBySize: (@Sendable (Int, Int) async -> Result<[String], ImageAnalysisError>?)? = nil,
      fetchGate: (@Sendable () async -> Void)? = nil,
      loadGate: (@Sendable (ImageAsset.ID) async -> Void)? = nil,
      deviceConditions: @escaping @Sendable () -> DeviceConditions = { normalConditions },
      now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }
    ) {
      let ids = ((album ?? []) + library).map(\.id)
      let widths = Dictionary(ids.enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
      let idsByWidth = Dictionary(widths.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      var loadResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = [:]
      for (id, width) in widths {
        loadResults[id] = loadErrors[id].map { .failure($0) }
          ?? .success(.stub(width: width, height: 1, isLocalFallback: fallbackIDs.contains(id)))
      }
      let log = EventLog()
      self.log = log
      self.photoLibrary = PhotoLibraryClientFake(
        currentState: access,
        imageAssets: library,
        loadImageResults: loadResults,
        albums: album.map { [RecordingMode.albumName: $0] } ?? [:],
        fetchGate: fetchGate,
        loadGate: loadGate
      )
      self.imageAnalysis = ImageAnalysisClientFake(
        classify: { image in
          let id = idsByWidth[image.cgImage.width] ?? ""
          log.append("classify:\(id)")
          await classifyGate(id)
          return classifyFailures.contains(id) ? .failure(.failed) : .success(labels[id] ?? [])
        },
        recognizeText: Self.recognizer(
          idsByWidth: idsByWidth,
          text: text,
          failures: recognizeFailures,
          bySize: recognizeBySize,
          log: log
        )
      )
      let library = SizedPhotoLibrary(
        base: self.photoLibrary,
        largestErrors: largestErrors,
        largestImages: largestImages,
        log: log
      )
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
      self.model = SampleRecorderModel(
        photoLibrary: library,
        imageAnalysis: self.imageAnalysis,
        deviceConditions: deviceConditions,
        now: now,
        calendar: calendar
      )
    }

    /// OCR Fake 의 결과. `bySize` 가 있으면 입력 크기로 고르고, 없거나 nil 을 주면 폭으로 이미지를 찾아 `text`·`failures` 로 고른다.
    nonisolated static func recognizer(
      idsByWidth: [Int: ImageAsset.ID],
      text: [ImageAsset.ID: [String]],
      failures: Set<ImageAsset.ID>,
      bySize: (@Sendable (Int, Int) async -> Result<[String], ImageAnalysisError>?)?,
      log: EventLog
    ) -> @Sendable (AnalysisImage) async -> Result<[RecognizedTextLine], ImageAnalysisError> {
      { image in
        let (width, height) = (image.cgImage.width, image.cgImage.height)
        let id = idsByWidth[width] ?? ""
        if let bySize {
          log.append("ocr:\(width)x\(height)")
          if let result = await bySize(width, height) {
            return result.map { $0.map(Self.line) }
          }
        } else {
          log.append("ocr:\(id)")
        }
        return failures.contains(id) ? .failure(.failed) : .success((text[id] ?? []).map(Self.line))
      }
    }

    nonisolated static func line(_ text: String) -> RecognizedTextLine {
      RecognizedTextLine(text: text, confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1))
    }

    /// 기록을 끝까지 돌린다.
    func record(_ mode: RecordingMode) async {
      self.model.modeChanged(mode)
      await self.model.startTapped()
    }
  }

  /// PhotoLibrary Fake 는 크기와 관계없이 같은 결과를 주므로, 원본만 실패하거나 원본만 다른 경우와 읽기 순서 기록을 이 대역이 더한다.
  struct SizedPhotoLibrary: PhotoLibraryClient {
    let base: PhotoLibraryClientFake
    let largestErrors: [ImageAsset.ID: ImageLoadError]
    let largestImages: [ImageAsset.ID: AnalysisImage]
    let log: EventLog

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
      self.log.append("load:\(id):\(size == .thumbnail ? "thumbnail" : "largest")")
      if size == .largestAvailable, let error = self.largestErrors[id] {
        _ = try? await self.base.loadImage(id: id, size: size)
        throw error
      }
      if size == .largestAvailable, let image = self.largestImages[id] {
        _ = try? await self.base.loadImage(id: id, size: size)
        return image
      }
      return try await self.base.loadImage(id: id, size: size)
    }

    @MainActor
    func presentLimitedLibraryPicker() async {
      await self.base.presentLimitedLibraryPicker()
    }

    func imageChanges() async -> AsyncStream<ImageChange> {
      await self.base.imageChanges()
    }
  }

  /// 여러 Task 의 Fake 가 함께 쓰는 호출 기록.
  final class EventLog: Sendable {
    private let events = Mutex<[String]>([])

    func append(_ event: String) {
      self.events.withLock { $0.append(event) }
    }

    var all: [String] {
      self.events.withLock { $0 }
    }
  }

  /// 테스트 도중 켜지는 표시. Fake 가 다른 Task 에서 켜고 테스트가 읽는다.
  final class Flag: Sendable {
    private let value = Mutex(false)

    func set() {
      self.value.withLock { $0 = true }
    }

    var isSet: Bool {
      self.value.withLock { $0 }
    }
  }

  /// 부를 때마다 다음 값을 주고, 다 쓰면 마지막 값을 계속 준다.
  final class ValueSequence<Value: Sendable>: Sendable {
    private let values: Mutex<[Value]>
    private let last: Value
    private let callCount = Mutex(0)

    init(_ values: [Value]) {
      precondition(!values.isEmpty)
      self.values = Mutex(values)
      self.last = values[values.count - 1]
    }

    func next() -> Value {
      self.callCount.withLock { $0 += 1 }
      return self.values.withLock { $0.isEmpty ? self.last : $0.removeFirst() }
    }

    /// `next()` 를 부른 횟수.
    var readCount: Int {
      self.callCount.withLock { $0 }
    }
  }

  /// 취소될 때까지 기다린다. 기다리기 시작하면 `started` 를 켠다.
  func waitUntilCancelled(_ started: Flag) async {
    started.set()
    try? await Task.sleep(for: .seconds(60))
  }

  /// 조건이 맞을 때까지 다른 Task 에 실행을 넘기며 기다린다.
  /// Fake 의 async 메서드는 전역 실행기에서 돌아 끝나는 시점이 스케줄링에 달렸으므로, 반복 횟수가 아니라 시간으로 제한한다.
  @MainActor
  func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
      await Task.yield()
    }
    #expect(condition(), "기다리던 상태가 되지 않았다")
  }

  extension Phase {
    /// 끝났거나 멈춘 기록의 결과.
    var result: RecordingResult? {
      switch self {
      case let .finished(result), let .cancelled(result, _): result
      default: nil
      }
    }

    var cancelReason: CancelReason? {
      if case let .cancelled(_, reason) = self {
        return reason
      }
      return nil
    }
  }

  extension FileOutput {
    var file: RecordedFile? {
      if case let .ready(file) = self {
        return file
      }
      return nil
    }
  }

  /// 결과 파일을 키 비교용으로 푼다.
  func jsonObject(_ output: FileOutput?) throws -> [String: Any] {
    let file = try #require(output?.file)
    return try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])
  }

  func jsonArray(_ output: FileOutput?) throws -> [[String: Any]] {
    let file = try #require(output?.file)
    return try #require(try JSONSerialization.jsonObject(with: file.data) as? [[String: Any]])
  }
#endif
