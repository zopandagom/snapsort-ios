// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisInterface
  import PhotoLibraryInterface

  /// 기록 한 번의 끝.
  enum RecordingOutcome: Sendable {
    /// 이미지를 하나도 처리하기 전에 멈췄다.
    case failed(RecordingFailure)
    case completed(RecordingResult)
    /// 취소되어 멈출 때까지 처리한 이미지의 부분 결과.
    case cancelled(RecordingResult)
  }

  /// 이미지 한 장을 잰 결과.
  enum MeasureOutcome: Sendable {
    /// 정확도 모드면 샘플 초안도 준다.
    case recorded(ImageMeasurement, SampleDraft?)
    case skipped(ImageMeasurement, SkippedImage)
    /// 취소되어 이 이미지는 남기지 않는다.
    case cancelled
  }

  /// `IndexingRun.analyze(_:)`(IndexingClientImpl.swift)와 같은 순서로 한 장씩 분석하며 단계별 시간을 잰다. 한쪽 순서를 바꾸면 다른 쪽도 맞춘다.
  /// 모든 시간은 메인 밖에서 `ContinuousClock` 으로 잰다.
  struct SampleRecording: Sendable {
    let photoLibrary: any PhotoLibraryClient
    let imageAnalysis: any ImageAnalysisClient
    let deviceConditions: @Sendable () -> DeviceConditions
    let now: @Sendable () -> Date
    let calendar: Calendar

    /// 기준 조정용으로 남기는 라벨 신뢰도 하한.
    static let labelRecordingFloor: Float = 0.01

    /// 비격리 함수 안에서 Task 를 만들어 메인 액터를 물려받지 않는다. 우선순위는 인덱서와 같은 `.utility`.
    /// 완료·취소·사전 실패 등 어느 경로로 끝나도 진행률 스트림을 끝내, 받는 쪽의 `for await` 가 빠져나오게 한다.
    nonisolated func start(
      mode: RecordingMode,
      progress: AsyncStream<RecordingProgress>.Continuation
    ) -> Task<RecordingOutcome, Never> {
      Task(priority: .utility) {
        defer { progress.finish() }
        return await self.run(mode: mode, progress: progress)
      }
    }

    /// 조회 → (속도 모드면 여행 판정 시간) → 이미지 루프 → 인코딩.
    /// 실패(`RecordingFailure`)는 이미지를 처리하기 전의 권한·조회 단계에서만 난다.
    @concurrent
    func run(mode: RecordingMode, progress: AsyncStream<RecordingProgress>.Continuation) async -> RecordingOutcome {
      let clock = ContinuousClock()
      let runStart = clock.now
      var run: RecordingRun
      switch await self.fetchTargets(mode: mode, clock: clock) {
      case let .ready(fetched):
        run = fetched
      case let .failed(failure):
        return .failed(failure)
      }
      run.fetchSeconds = runStart.duration(to: clock.now).seconds

      // 조회 도중 취소됐으면 이미지 0장의 부분 결과로 끝낸다.
      var wasCancelled = Task.isCancelled
      if !wasCancelled {
        progress.yield(run.progress)
      }
      for (index, asset) in run.targets.enumerated() where !wasCancelled {
        if Task.isCancelled {
          wasCancelled = true
          break
        }
        let state = self.deviceConditions().thermalState
        if run.thermalStateChanges.last?.state != state {
          run.thermalStateChanges.append(ThermalStateChange(index: index, state: state))
        }
        wasCancelled = await !run.append(self.measure(asset, index: index, mode: mode))
        if !wasCancelled {
          progress.yield(run.progress)
        }
      }

      run.totalSeconds = runStart.duration(to: clock.now).seconds
      let result = run.result(conditionsAtEnd: self.deviceConditions(), recordedAt: self.now(), calendar: self.calendar)
      return wasCancelled ? .cancelled(result) : .completed(result)
    }

    /// 이미지 한 장을 운영 인덱서와 같은 순서로 분석하며 단계마다 시간을 잰다.
    /// 정확도 모드는 OCR 대상이 아니어도 원본을 읽어 OCR 한다(판정 규칙을 바꿔도 다시 기록하지 않도록).
    /// 그래서 원본 로드나 OCR 에 실패하면 OCR 대상이 아니어도 건너뛴다. OCR 줄 없이 기록하면 OCR 대상 조건을 바꾸는 실험에서
    /// 그 샘플이 틀린 입력이 되기 때문이다.
    @concurrent
    func measure(_ asset: ImageAsset, index: Int, mode: RecordingMode) async -> MeasureOutcome {
      let clock = ContinuousClock()
      let start = clock.now
      var measurement = ImageMeasurement(index: index, asset: asset)
      var stage = SkippedImage.Stage.thumbnailLoad
      do throws(MeasureStop) {
        let labels = try await self.classify(asset, measurement: &measurement, stage: &stage, clock: clock)
        // 운영과 같은 기준으로 거른 라벨로 OCR 대상을 판정한다. 시간은 재지 않는다.
        let ruleLabels = labels.filter { $0.confidence >= ClassificationRules.minimumLabelConfidence }
        let needsText = TextRecognitionPolicy.needsTextRecognition(asset: asset, labels: ruleLabels)
        measurement.needsTextRecognition = needsText

        var textLines: [RecognizedTextLine] = []
        // 정확도 모드는 OCR 대상이 아니어도 OCR 하고, 실패하면 건너뛴다(measure 문서 주석).
        if mode == .accuracy || needsText {
          textLines = try await self.recognizeText(asset, measurement: &measurement, stage: &stage, clock: clock)
        }

        measurement.totalMs = start.duration(to: clock.now).milliseconds
        measurement.pipelineMs = Self.pipelineMs(of: measurement, needsText: needsText)
        guard mode == .accuracy else { return .recorded(measurement, nil) }
        // Core 테스트 `ClassificationSample.classify()` 와 같은 계산이다.
        let predicted = RuleClassifier.classify(
          asset: asset,
          labels: ruleLabels,
          textLines: needsText ? textLines : []
        )
        let draft = SampleDraft(index: index, asset: asset, labels: labels, textLines: textLines, predicted: predicted)
        return .recorded(measurement, draft)
      } catch {
        switch error {
        case .cancelled:
          return .cancelled
        case let .skipped(reason):
          measurement.outcome = .skipped
          measurement.skipReason = reason
          measurement.failedStage = stage
          measurement.totalMs = start.duration(to: clock.now).milliseconds
          return .skipped(measurement, SkippedImage(index: index, reason: reason, stage: stage))
        }
      }
    }

    /// 운영 인덱서가 하는 단계만 더한다: 썸네일 로드 + 분류, OCR 대상이면 원본 로드 + OCR.
    static func pipelineMs(of measurement: ImageMeasurement, needsText: Bool) -> Double? {
      guard let thumbnailLoadMs = measurement.thumbnailLoadMs, let classifyMs = measurement.classifyMs else {
        return nil
      }
      guard needsText else { return thumbnailLoadMs + classifyMs }
      guard let largestLoadMs = measurement.largestLoadMs, let ocrMs = measurement.ocrMs else { return nil }
      return thumbnailLoadMs + classifyMs + largestLoadMs + ocrMs
    }

    // MARK: - Private

    /// 권한을 확인하고 대상 이미지를 조회한다. 속도 모드는 인덱서처럼 보관함 전체로 여행 판정 시간을 한 번 잰다(결과는 버린다).
    /// 기기 상태 시작값은 권한 확인 뒤 조회 직전에 읽는다. `deviceConditions` 는 시작값 → 이미지마다 → 끝값 순서로 부르고,
    /// 여기서 실패하면 끝값은 읽지 않는다.
    private func fetchTargets(
      mode: RecordingMode,
      clock: ContinuousClock
    ) async -> FetchOutcome {
      let access = self.photoLibrary.accessState()
      guard access.canRead else { return .failed(.notAuthorized) }
      if mode == .accuracy, access == .limited {
        return .failed(.limitedAccess)
      }
      let conditionsAtStart = self.deviceConditions()
      switch mode {
      case .accuracy:
        guard let album = await self.photoLibrary.fetchImageAssets(inAlbumNamed: RecordingMode.albumName) else {
          return .failed(.albumNotFound)
        }
        guard !album.isEmpty else { return .failed(.albumEmpty) }
        return .ready(RecordingRun(
          mode: mode,
          access: access,
          targets: album,
          conditionsAtStart: conditionsAtStart
        ))
      case let .speed(count):
        let library = await self.photoLibrary.fetchImageAssets()
        guard !library.isEmpty else { return .failed(.noImages) }
        var run = RecordingRun(
          mode: mode,
          access: access,
          targets: Array(library.prefix(count)),
          conditionsAtStart: conditionsAtStart
        )
        run.libraryCount = library.count
        let travelStart = clock.now
        _ = TravelDetector.trips(in: library, calendar: self.calendar)
        run.travelDetectionMs = travelStart.duration(to: clock.now).milliseconds
        return .ready(run)
      }
    }

    /// 썸네일을 읽어 기록 하한으로 분류한다.
    private func classify(
      _ asset: ImageAsset,
      measurement: inout ImageMeasurement,
      stage: inout SkippedImage.Stage,
      clock: ContinuousClock
    ) async throws(MeasureStop) -> [ImageLabel] {
      stage = .thumbnailLoad
      var stepStart = clock.now
      let thumbnail = try await self.loadImage(asset.id, size: .thumbnail)
      measurement.thumbnailLoadMs = stepStart.duration(to: clock.now).milliseconds
      measurement.thumbnailPixelWidth = thumbnail.cgImage.width
      measurement.thumbnailPixelHeight = thumbnail.cgImage.height
      measurement.thumbnailFallback = thumbnail.isLocalFallback

      stage = .classify
      stepStart = clock.now
      let labels = try await self.analysis { () async throws(ImageAnalysisError) in
        try await self.imageAnalysis.classify(thumbnail, minimumConfidence: Self.labelRecordingFloor)
      }
      measurement.classifyMs = stepStart.duration(to: clock.now).milliseconds
      measurement.labelCount = labels.count
      return labels
    }

    /// 기기에 있는 가장 큰 버전을 읽어 OCR 한다.
    private func recognizeText(
      _ asset: ImageAsset,
      measurement: inout ImageMeasurement,
      stage: inout SkippedImage.Stage,
      clock: ContinuousClock
    ) async throws(MeasureStop) -> [RecognizedTextLine] {
      stage = .largestLoad
      var stepStart = clock.now
      let image = try await self.loadImage(asset.id, size: .largestAvailable)
      measurement.largestLoadMs = stepStart.duration(to: clock.now).milliseconds
      measurement.ocrPixelWidth = image.cgImage.width
      measurement.ocrPixelHeight = image.cgImage.height
      measurement.ocrFallback = image.isLocalFallback

      stage = .ocr
      stepStart = clock.now
      let textLines = try await self.analysis { () async throws(ImageAnalysisError) in
        try await self.imageAnalysis.recognizeText(image)
      }
      measurement.ocrMs = stepStart.duration(to: clock.now).milliseconds
      measurement.textLineCount = textLines.count
      return textLines
    }

    private func loadImage(_ id: ImageAsset.ID, size: ImageSize) async throws(MeasureStop) -> AnalysisImage {
      do throws(ImageLoadError) {
        return try await self.photoLibrary.loadImage(id: id, size: size)
      } catch {
        switch error {
        case .cancelled: throw .cancelled
        case .notFound: throw .skipped(.gone)
        case .notAvailableLocally, .failed: throw .skipped(.unavailable)
        }
      }
    }

    private func analysis<Output>(
      _ operation: () async throws(ImageAnalysisError) -> Output
    ) async throws(MeasureStop) -> Output {
      do throws(ImageAnalysisError) {
        return try await operation()
      } catch {
        switch error {
        case .cancelled: throw .cancelled
        case .failed: throw .skipped(.analysisFailed)
        }
      }
    }
  }

  /// 기록 한 번 동안 모으는 값. `SampleRecording.run` 안에서만 쓴다.
  struct RecordingRun {
    let mode: RecordingMode
    let access: PhotoAccessState
    let targets: [ImageAsset]
    /// 조회 직전에 읽은 기기 상태.
    let conditionsAtStart: DeviceConditions
    var libraryCount: Int?
    var travelDetectionMs: Double?
    var fetchSeconds: Double = 0
    var totalSeconds: Double = 0
    var measurements: [ImageMeasurement] = []
    var drafts: [SampleDraft] = []
    var skipped: [SkippedImage] = []
    /// 이미지마다 썸네일 로드 직전에 읽은 발열 상태가 직전과 다를 때만 붙인다. 처리를 시작한 이미지가 없으면 비어 있다.
    /// 건너뛴 이미지도 남는다(요약 통계에서는 빠진다).
    var thermalStateChanges: [ThermalStateChange] = []

    var progress: RecordingProgress {
      RecordingProgress(
        mode: self.mode,
        total: self.targets.count,
        processed: self.measurements.count,
        skipped: self.skipped.count,
        fallbackCount: self.measurements.count(where: \.usedFallback),
        isCancelling: false
      )
    }

    /// 한 장의 결과를 더한다. 취소면 아무것도 더하지 않고 false.
    mutating func append(_ outcome: MeasureOutcome) -> Bool {
      switch outcome {
      case let .recorded(measurement, draft):
        self.measurements.append(measurement)
        if let draft {
          self.drafts.append(draft)
        }
      case let .skipped(measurement, skippedImage):
        self.measurements.append(measurement)
        self.skipped.append(skippedImage)
      case .cancelled:
        return false
      }
      return true
    }

    /// 끝(완료·취소 모두)의 조건으로 요약을 계산하고 두 파일을 따로 인코딩한다. 기록한 샘플이 0장이면 샘플 파일은 없다.
    func result(conditionsAtEnd: DeviceConditions, recordedAt: Date, calendar: Calendar) -> RecordingResult {
      let summary = TimingSummary.make(from: self.measurements, thermalChanges: self.thermalStateChanges)
      let timeZone = calendar.timeZone
      let samplesFile: FileOutput? = self.mode == .accuracy && !self.drafts.isEmpty
        ? RecordingOutput.encode(
          self.drafts,
          fileName: RecordingOutput.samplesFileName(at: recordedAt, timeZone: timeZone)
        )
        : nil
      let timing = TimingFile(
        run: self,
        summary: summary,
        conditionsAtEnd: conditionsAtEnd,
        recordedAt: recordedAt
      )
      return RecordingResult(
        mode: self.mode,
        summary: summary,
        samplesFile: samplesFile,
        timingFile: RecordingOutput.encode(
          timing,
          fileName: RecordingOutput.timingFileName(mode: self.mode, at: recordedAt, timeZone: timeZone)
        ),
        recordedSampleCount: self.drafts.count,
        skipped: self.skipped,
        fallbackCount: summary.fallbackCount,
        totalSeconds: self.totalSeconds,
        conditionsAtStart: self.conditionsAtStart,
        conditionsAtEnd: conditionsAtEnd,
        thermalStateChanges: self.thermalStateChanges
      )
    }
  }

  /// 이미지를 처리하기 전 권한·조회 단계의 결과.
  private enum FetchOutcome {
    case ready(RecordingRun)
    case failed(RecordingFailure)
  }

  /// 이미지 한 장의 측정을 멈추는 이유.
  private enum MeasureStop: Error {
    /// Task 가 취소됐다. 이 이미지는 남기지 않고 기록을 멈춘다.
    case cancelled
    /// 이 이미지만 건너뛴다.
    case skipped(SkippedImage.Reason)
  }

  private extension Duration {
    var milliseconds: Double {
      Double(self.components.seconds) * 1000 + Double(self.components.attoseconds) / 1e15
    }

    var seconds: Double {
      self.milliseconds / 1000
    }
  }
#endif
