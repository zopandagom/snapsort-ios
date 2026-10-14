// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import CoreTransferable
  import Foundation
  import PhotoLibraryInterface
  import UniformTypeIdentifiers

  /// 공유 시트(`ActivityView`)로 넘기는 JSON. `NSItemProvider` 로 Data 를 넘겨 우리 코드는 파일을 쓰지 않는다.
  public struct RecordedFile: Sendable, Equatable, Identifiable, Transferable {
    public let fileName: String
    public let data: Data

    public var id: String { self.fileName }

    public static var transferRepresentation: some TransferRepresentation {
      DataRepresentation(exportedContentType: .json) { $0.data }
        .suggestedFileName { $0.fileName }
    }
  }

  /// 정확도 샘플 초안 한 장. 사람이 `predicted` 를 보고 `expected` 를 채운 뒤 `predicted` 를 지워 픽스처에 넣는다.
  /// 키는 Core Tests `ClassificationSample`(ClassificationAccuracyTests.swift)과 짝이다. 한쪽을 바꾸면 다른 쪽도 맞춘다.
  /// 좌표·식별자·날짜는 넣지 않는다.
  struct SampleDraft: Sendable, Equatable, Encodable {
    struct Asset: Sendable, Equatable, Encodable {
      let isScreenshot: Bool
      let hasLocation: Bool
      let pixelWidth: Int
      let pixelHeight: Int
    }

    struct Label: Sendable, Equatable, Encodable {
      let identifier: String
      /// 소수 3자리로 내린 신뢰도.
      let confidence: Double
    }

    let name: String
    let asset: Asset
    let labels: [Label]
    let text: [String]
    /// 규칙 분류 결과의 rawValue 를 정렬한 것.
    let predicted: [String]
  }

  extension SampleDraft {
    /// 처리 순서 `index` 의 앨범 이미지. 라벨은 받은 순서(신뢰도 높은 순) 그대로 두고 신뢰도를 내린다.
    init(
      index: Int,
      asset: ImageAsset,
      labels: [ImageLabel],
      textLines: [RecognizedTextLine],
      predicted: Set<ImageCategory>
    ) {
      self.init(
        name: String(format: "앨범 %03d", index + 1),
        asset: Asset(
          isScreenshot: asset.isScreenshot,
          hasLocation: asset.coordinate != nil,
          pixelWidth: asset.pixelWidth,
          pixelHeight: asset.pixelHeight
        ),
        labels: labels.map {
          Label(identifier: $0.identifier, confidence: RecordingOutput.truncatedConfidence($0.confidence))
        },
        text: textLines.map(\.text),
        predicted: predicted.map(\.rawValue).sorted()
      )
    }
  }

  /// 측정 파일. OCR 텍스트·라벨·식별자·촬영 날짜는 넣지 않는다. 값이 nil 인 필드는 빠진다.
  struct TimingFile: Encodable {
    let mode: String
    let requestedCount: Int?
    let libraryCount: Int?
    let processedCount: Int
    let recordedAt: Date
    /// 기기 모델 식별자(예: "iPhone17,1"). 사용자가 붙인 기기 이름은 넣지 않는다.
    let device: String
    let osVersion: String
    let access: String
    let priority: String
    let labelRecordingFloor: Double
    let labelConfidenceThreshold: Double
    let fetchSeconds: Double
    let travelDetectionMs: Double?
    let totalSeconds: Double
    let thermalStateAtStart: ThermalState
    let thermalStateAtEnd: ThermalState
    let lowPowerModeAtStart: Bool
    let lowPowerModeAtEnd: Bool
    let thermalStateChanges: [ThermalStateChange]
    let limitations: [String]
    let summary: TimingSummary
    let images: [ImageMeasurement]

    init(run: RecordingRun, summary: TimingSummary, conditionsAtEnd: DeviceConditions, recordedAt: Date) {
      if case let .speed(count) = run.mode {
        self.mode = "speed"
        self.requestedCount = count
      } else {
        self.mode = "accuracy"
        self.requestedCount = nil
      }
      self.libraryCount = run.libraryCount
      self.processedCount = run.measurements.count
      self.recordedAt = recordedAt
      self.device = Self.deviceModel
      let version = ProcessInfo.processInfo.operatingSystemVersion
      self.osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
      self.access = run.access == .limited ? "limited" : "authorized"
      self.priority = "utility"
      self.labelRecordingFloor = RecordingOutput.decimalValue(SampleRecording.labelRecordingFloor)
      self.labelConfidenceThreshold = RecordingOutput.decimalValue(ClassificationRules.minimumLabelConfidence)
      self.fetchSeconds = run.fetchSeconds
      self.travelDetectionMs = run.travelDetectionMs
      self.totalSeconds = run.totalSeconds
      self.thermalStateAtStart = run.conditionsAtStart.thermalState
      self.thermalStateAtEnd = conditionsAtEnd.thermalState
      self.lowPowerModeAtStart = run.conditionsAtStart.isLowPowerModeEnabled
      self.lowPowerModeAtEnd = conditionsAtEnd.isLowPowerModeEnabled
      self.thermalStateChanges = run.thermalStateChanges
      self.limitations = Self.limitations
      self.summary = summary
      self.images = run.measurements
    }

    /// 기기 모델 식별자(utsname.machine). 사용자가 붙인 기기 이름(UIDevice.name)은 쓰지 않는다.
    private static var deviceModel: String {
      var systemInfo = utsname()
      uname(&systemInfo)
      let machine = withUnsafeBytes(of: &systemInfo.machine) { Array($0.prefix { $0 != 0 }) }
      return String(bytes: machine, encoding: .utf8) ?? "unknown"
    }

    static let limitations = [
      "저장소 저장·삭제 시간은 재지 않는다.",
      "인덱서가 이미 읽은 썸네일은 사진 캐시로 더 빠를 수 있다.",
      "첫 이미지에는 Vision 모델 로딩이 들어간다(firstImagePipelineMs 로 따로 본다).",
      "정확도 모드는 OCR 대상이 아니어도 OCR 하므로 운영 시간은 pipeline 으로 본다.",
      "totalMs 는 메인 밖에서 잰 한 장의 경과 시간이며 화면 갱신을 포함하지 않는다.",
      "발열 상태는 이미지 시작 시점마다 읽어 이미지 사이의 짧은 변화는 놓칠 수 있다.",
    ]
  }

  /// 시간 값 묶음의 요약. p50·p95 는 최근접 순위로 고른다.
  public struct Stats: Sendable, Equatable, Encodable {
    public let count: Int
    public let meanMs: Double
    public let p50Ms: Double
    public let p95Ms: Double
    public let maxMs: Double
  }

  /// 측정 결과 요약. 화면과 측정 파일의 `summary` 가 함께 쓴다.
  public struct TimingSummary: Sendable, Equatable, Encodable {
    public struct ThermalStateStats: Sendable, Equatable, Encodable {
      public let nominal: Stats?
      public let fair: Stats?
      public let serious: Stats?
      public let critical: Stats?
      public let unknown: Stats?

      public subscript(state: ThermalState) -> Stats? {
        switch state {
        case .nominal: self.nominal
        case .fair: self.fair
        case .serious: self.serious
        case .critical: self.critical
        case .unknown: self.unknown
        }
      }
    }

    public struct SkippedCounts: Sendable, Equatable, Encodable {
      public let unavailable: Int
      public let gone: Int
      public let analysisFailed: Int
    }

    public let thumbnailLoad: Stats?
    public let classify: Stats?
    public let largestLoad: Stats?
    public let ocr: Stats?
    /// 운영 인덱서가 하는 단계만 더한 시간(`ImageMeasurement.pipelineMs`).
    public let pipeline: Stats?
    /// 기록한 이미지의 한 장 경과 시간(`ImageMeasurement.totalMs`).
    public let total: Stats?
    /// 이미지를 시작할 때의 발열 상태별 pipeline.
    public let byThermalState: ThermalStateStats
    /// 처음 기록한 이미지의 pipeline. Vision 모델 로딩이 들어가 따로 본다.
    public let firstImagePipelineMs: Double?
    public let ocrTargetCount: Int
    /// OCR 대상 수 / 분류까지 마친 수. 분류까지 마친 이미지가 없으면 nil.
    public let ocrTargetRatio: Double?
    public let fallbackCount: Int
    public let skipped: SkippedCounts

    /// - Parameter thermalChanges: 발열 상태가 바뀐 이미지 순서. 이미지 i 의 상태는 `index ≤ i` 인 마지막 변화다.
    nonisolated static func make(
      from measurements: [ImageMeasurement],
      thermalChanges: [ThermalStateChange]
    ) -> TimingSummary {
      let recorded = measurements.filter { $0.outcome == .recorded }
      let classified = measurements.filter { $0.needsTextRecognition != nil }
      let ocrTargetCount = classified.count { $0.needsTextRecognition == true }
      var pipelineByState: [ThermalState: [Double]] = [:]
      for measurement in recorded {
        guard let pipelineMs = measurement.pipelineMs else { continue }
        let state = thermalChanges.last { $0.index <= measurement.index }?.state ?? .unknown
        pipelineByState[state, default: []].append(pipelineMs)
      }
      let skipped = measurements.filter { $0.outcome == .skipped }
      return TimingSummary(
        thumbnailLoad: self.stats(measurements.compactMap(\.thumbnailLoadMs)),
        classify: self.stats(measurements.compactMap(\.classifyMs)),
        largestLoad: self.stats(measurements.compactMap(\.largestLoadMs)),
        ocr: self.stats(measurements.compactMap(\.ocrMs)),
        pipeline: self.stats(recorded.compactMap(\.pipelineMs)),
        total: self.stats(recorded.map(\.totalMs)),
        byThermalState: ThermalStateStats(
          nominal: self.stats(pipelineByState[.nominal] ?? []),
          fair: self.stats(pipelineByState[.fair] ?? []),
          serious: self.stats(pipelineByState[.serious] ?? []),
          critical: self.stats(pipelineByState[.critical] ?? []),
          unknown: self.stats(pipelineByState[.unknown] ?? [])
        ),
        firstImagePipelineMs: recorded.min { $0.index < $1.index }?.pipelineMs,
        ocrTargetCount: ocrTargetCount,
        ocrTargetRatio: classified.isEmpty ? nil : Double(ocrTargetCount) / Double(classified.count),
        fallbackCount: measurements.count(where: \.usedFallback),
        skipped: SkippedCounts(
          unavailable: skipped.count { $0.skipReason == .unavailable },
          gone: skipped.count { $0.skipReason == .gone },
          analysisFailed: skipped.count { $0.skipReason == .analysisFailed }
        )
      )
    }

    /// 값이 없으면 nil. p50·p95 는 정렬한 값에서 `ceil(p·n) - 1` 번째(최근접 순위)다.
    nonisolated static func stats(_ values: [Double]) -> Stats? {
      guard !values.isEmpty else { return nil }
      let sorted = values.sorted()
      let count = sorted.count
      func percentile(_ fraction: Double) -> Double {
        sorted[max(Int((fraction * Double(count)).rounded(.up)) - 1, 0)]
      }
      return Stats(
        count: count,
        meanMs: sorted.reduce(0, +) / Double(count),
        p50Ms: percentile(0.5),
        p95Ms: percentile(0.95),
        maxMs: sorted[count - 1]
      )
    }
  }

  enum RecordingOutput {
    /// 픽스처에 옮겨도 기준을 넘는 쪽으로 바뀌지 않도록 신뢰도를 소수 3자리로 내린다.
    /// `Float` 를 그대로 `Double` 로 바꾸면 0.7 이 0.69999… 가 되어 한 자리 아래로 내려가므로, 십진 표기에서 내린다.
    /// 유한하지 않은 값은 그대로 두어 인코딩이 실패하게 한다.
    static func truncatedConfidence(_ confidence: Float) -> Double {
      guard confidence.isFinite, var value = Decimal(string: String(describing: confidence)) else {
        return Double(confidence)
      }
      var truncated = Decimal()
      NSDecimalRound(&truncated, &value, 3, .down)
      return Double("\(truncated)") ?? Double(confidence)
    }

    /// `Float` 기준 값을 측정 파일에 적힌 그대로(예: 0.01) 남긴다.
    static func decimalValue(_ value: Float) -> Double {
      Double(String(describing: value)) ?? Double(value)
    }

    /// 샘플 초안 파일 이름. 시각은 `timeZone` 기준이다.
    static func samplesFileName(at date: Date, timeZone: TimeZone) -> String {
      "ClassificationSamples-draft-\(self.timestamp(date, timeZone: timeZone)).json"
    }

    /// 측정 파일 이름. 시각은 `timeZone` 기준이다.
    static func timingFileName(mode: RecordingMode, at date: Date, timeZone: TimeZone) -> String {
      "IndexingTiming-\(mode.fileTag)-\(self.timestamp(date, timeZone: timeZone)).json"
    }

    /// 사람이 읽고 비교하기 쉽게 키를 정렬해 들여 쓴다. 실패하면 그 파일만 `.encodingFailed` 다.
    static func encode(_ value: some Encodable, fileName: String) -> FileOutput {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      encoder.dateEncodingStrategy = .iso8601
      do {
        return try .ready(RecordedFile(fileName: fileName, data: encoder.encode(value)))
      } catch {
        return .encodingFailed
      }
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = timeZone
      formatter.dateFormat = "yyyyMMdd-HHmm"
      return formatter.string(from: date)
    }
  }
#endif
