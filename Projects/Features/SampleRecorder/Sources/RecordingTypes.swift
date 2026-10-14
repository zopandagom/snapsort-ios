// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import Foundation

  /// 기록할 이미지를 고르는 방법.
  public enum RecordingMode: Sendable, Hashable {
    /// 앨범 `albumName` 의 이미지를 앨범 순서로 기록한다. 정확도 샘플 초안과 측정 파일을 만든다.
    case accuracy
    /// 보관함 최신 `count` 장의 단계별 시간을 잰다. 측정 파일만 만든다.
    case speed(count: Int)
    /// 보관함 최신 `count` 장 중 OCR 대상(운영 기준)의 원본을 낮은 상한(`OCRResolutionCap.all`)으로 줄여 다시 OCR 하고
    /// 현재 상한(기준)과 비교한다. 단계별 시간은 속도 모드와 같이 기준 값으로 잰다. 측정 파일만 만든다.
    case ocrResolution(count: Int)

    public static let speedCounts = [100, 1000, 10000]
    public static let ocrResolutionCounts = [100, 1000]
    public static let albumName = "SnapSort 샘플"

    /// 측정 파일 이름과 `mode` 값에 쓰는 이름.
    var fileTag: String {
      switch self {
      case .accuracy: "accuracy"
      case let .speed(count): "speed\(count)"
      case let .ocrResolution(count): "ocrResolution\(count)"
      }
    }
  }

  /// 기록 화면의 단계.
  public enum Phase: Sendable, Equatable {
    case idle
    case recording(RecordingProgress)
    case finished(RecordingResult)
    /// 멈출 때까지 처리한 이미지의 부분 결과.
    case cancelled(RecordingResult, reason: CancelReason)
    /// 이미지를 하나도 처리하기 전에 멈춘 이유.
    case failed(RecordingFailure)
  }

  public struct RecordingProgress: Sendable, Equatable {
    public let mode: RecordingMode
    /// 처리할 이미지 수. 조회 전에는 0.
    public let total: Int
    /// 기록하거나 건너뛴 이미지 수.
    public let processed: Int
    public let skipped: Int
    /// iCloud 대체 버전으로 읽은 이미지 수.
    public let fallbackCount: Int
    /// 멈추라는 신호를 받고 지금 이미지가 끝나기를 기다리는 중인지.
    public let isCancelling: Bool

    /// 조회 전의 진행률.
    static func starting(_ mode: RecordingMode) -> RecordingProgress {
      RecordingProgress(mode: mode, total: 0, processed: 0, skipped: 0, fallbackCount: 0, isCancelling: false)
    }

    func cancelling(_ isCancelling: Bool) -> RecordingProgress {
      RecordingProgress(
        mode: self.mode,
        total: self.total,
        processed: self.processed,
        skipped: self.skipped,
        fallbackCount: self.fallbackCount,
        isCancelling: isCancelling
      )
    }
  }

  /// 기록을 멈춘 이유. 처음 받은 이유만 남긴다.
  public enum CancelReason: Sendable, Equatable {
    case user
    case background
    case screenClosed
  }

  public enum RecordingFailure: Sendable, Equatable {
    /// 사진을 읽을 권한이 없다.
    case notAuthorized
    /// 정확도 모드는 사용자 앨범을 읽어야 해서 전체 접근에서만 된다.
    case limitedAccess
    case albumNotFound
    case albumEmpty
    /// 보관함에서 고르는 모드(속도·OCR 해상도 비교)인데 보관함에 이미지가 없다.
    case noImages
  }

  public struct RecordingResult: Sendable, Equatable {
    public let mode: RecordingMode
    /// 화면에 보이는 요약. 측정 파일의 `summary` 와 같다.
    public let summary: TimingSummary
    /// 정확도 모드의 샘플 초안. 정확도 모드가 아니거나 기록한 샘플이 0장이면 nil.
    public let samplesFile: FileOutput?
    public let timingFile: FileOutput
    public let recordedSampleCount: Int
    /// 건너뛴 이미지. 화면은 이유별 개수로 보인다(SkippedImage).
    public let skipped: [SkippedImage]
    public let fallbackCount: Int
    /// 조회부터 끝까지 걸린 시간(초).
    public let totalSeconds: Double
    public let conditionsAtStart: DeviceConditions
    public let conditionsAtEnd: DeviceConditions
    /// 발열 상태가 바뀐 이미지와 그 상태. 첫 원소는 첫 이미지의 상태다.
    public let thermalStateChanges: [ThermalStateChange]
    /// OCR 해상도 비교 요약. 측정 파일의 `ocrResolution.summary` 와 같다. 다른 모드는 nil.
    public let ocrComparison: OCRResolutionSummary?
  }

  /// 만든 결과 파일. 인코딩에 실패하면 그 파일만 공유하지 못한다.
  public enum FileOutput: Sendable, Equatable {
    case ready(RecordedFile)
    case encodingFailed
  }

  /// 건너뛴 이미지(식별자 없이 처리 순서·이유·단계). 화면은 이유별 개수만 보이고, 측정 파일은 `images` 의 `index`·`skipReason`·`failedStage` 로 남긴다.
  public struct SkippedImage: Sendable, Equatable, Encodable {
    public enum Reason: String, Sendable, Equatable, Encodable, CaseIterable {
      /// iCloud 에만 있거나 손상돼 읽지 못했다.
      case unavailable
      /// 보관함에 없다.
      case gone
      case analysisFailed
    }

    public enum Stage: String, Sendable, Equatable, Encodable {
      case thumbnailLoad
      case classify
      case largestLoad
      case ocr
    }

    /// 처리 순서(정확도 모드는 앨범 순서), 0부터.
    public let index: Int
    public let reason: Reason
    public let stage: Stage
  }

  /// 측정에 영향을 주는 기기 상태.
  public struct DeviceConditions: Sendable, Equatable {
    public let thermalState: ThermalState
    public let isLowPowerModeEnabled: Bool

    public init(thermalState: ThermalState, isLowPowerModeEnabled: Bool) {
      self.thermalState = thermalState
      self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    /// 지금 기기 상태를 읽는다.
    public static let current: @Sendable () -> DeviceConditions = {
      DeviceConditions(
        thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
        isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
      )
    }
  }

  public enum ThermalState: String, Sendable, Equatable, Encodable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    init(_ state: ProcessInfo.ThermalState) {
      switch state {
      case .nominal: self = .nominal
      case .fair: self = .fair
      case .serious: self = .serious
      case .critical: self = .critical
      @unknown default: self = .unknown
      }
    }
  }

  /// 처리 순서 `index` 의 이미지부터 발열 상태가 `state` 다.
  public struct ThermalStateChange: Sendable, Equatable, Encodable {
    public let index: Int
    public let state: ThermalState
  }

  /// 이미지 한 장의 측정 레코드. 식별자·라벨·OCR 텍스트·촬영 날짜는 담지 않는다.
  /// 값이 없는 단계는 nil 이고, 측정 파일에서 키가 빠진다.
  /// OCR 해상도 비교 모드에서 원본·OCR 필드(`largestLoadMs`·`ocr…`·`textLineCount`)는 기준(현재 상한) 값이고, 낮은 상한 값은 `ocrComparison` 에 있다.
  struct ImageMeasurement: Sendable, Equatable, Encodable {
    enum Outcome: String, Sendable, Encodable {
      case recorded
      case skipped
    }

    let index: Int
    let isScreenshot: Bool
    let hasLocation: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    var outcome = Outcome.recorded
    var skipReason: SkippedImage.Reason?
    var failedStage: SkippedImage.Stage?
    var thumbnailLoadMs: Double?
    var thumbnailPixelWidth: Int?
    var thumbnailPixelHeight: Int?
    var thumbnailFallback: Bool?
    var classifyMs: Double?
    var labelCount: Int?
    var needsTextRecognition: Bool?
    var largestLoadMs: Double?
    var ocrPixelWidth: Int?
    var ocrPixelHeight: Int?
    var ocrFallback: Bool?
    var ocrMs: Double?
    var textLineCount: Int?
    /// 썸네일 로드 시작부터 마지막 단계 끝까지.
    var totalMs: Double = 0
    /// 운영 인덱서가 하는 단계만 더한 시간: 썸네일 로드 + 분류, OCR 대상이면 원본 로드 + OCR. 건너뛴 이미지는 nil.
    var pipelineMs: Double?
    /// OCR 해상도 비교 모드에서 OCR 대상을 기록했을 때만 있다.
    var ocrComparison: OCRComparisonRecord?

    init(index: Int, asset: ImageAsset) {
      self.index = index
      self.isScreenshot = asset.isScreenshot
      self.hasLocation = asset.coordinate != nil
      self.pixelWidth = asset.pixelWidth
      self.pixelHeight = asset.pixelHeight
    }

    /// 썸네일이나 원본을 iCloud 대체 버전으로 읽었는지.
    var usedFallback: Bool {
      self.thumbnailFallback == true || self.ocrFallback == true
    }
  }
#endif
